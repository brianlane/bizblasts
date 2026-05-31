# frozen_string_literal: true

# Main orchestration service for CNAME custom domain setup
# Coordinates between Render API, DNS checking, and email notifications
class CnameSetupService
  class SetupError < StandardError; end
  class InvalidBusinessError < SetupError; end
  class DomainAlreadyExistsError < SetupError; end

  # Initialize the service
  #
  # We avoid eagerly instantiating RenderDomainService because many code paths
  # (e.g. querying the current status) do **not** require hitting the Render API
  # and therefore should not fail when the Render credentials are not present
  # (such as in test environments).
  #
  # Instead we accept an optional `render_service` dependency that can be
  # supplied by callers/tests.  When it is first needed we lazily create a
  # concrete RenderDomainService instance, which will still raise an
  # InvalidCredentialsError if the credentials are missing *and* we actually
  # need to talk to the API.
  def initialize(business, render_service: nil)
    @business = business
    @render_service = render_service # may be nil – we will lazily build when required
    @errors = []
  end

  # Lazily build or return the active domain-provider instance. On Render
  # this returns a RenderDomainService; on the Ubuntu/Caddy deployment it
  # returns a CaddyDomainService (selected by DomainProvider). The variable
  # is named `render_service` for historical reasons — both providers
  # implement the same public API.
  def render_service
    @render_service ||= DomainProvider.current
  end

  # Start the complete CNAME setup process
  # @return [Hash] Result with success status and details
  def start_setup!
    Rails.logger.info "[CnameSetupService] Starting setup for business #{@business.id} (#{@business.hostname})"

    begin
      # Validate business can setup custom domain
      validate_business_eligibility!

      # Step 1: Add domain to Render
      add_domain_to_render!

      # Step 1.5: Trigger verification for both apex and www domains
      verify_render_domains!

      # Step 2: Update business status and start monitoring
      update_business_status!

      # Step 3: Send setup instructions email
      send_setup_instructions!

      # Step 4: Start DNS monitoring
      start_monitoring!

      Rails.logger.info "[CnameSetupService] Setup initiated successfully for #{@business.hostname}"

      {
        success: true,
        message: 'Custom domain setup initiated successfully',
        business_id: @business.id,
        domain: @business.hostname,
        status: @business.status,
        next_steps: setup_next_steps
      }

    rescue => e
      Rails.logger.error "[CnameSetupService] Setup failed: #{e.message}"
      
      # Rollback any partial changes
      rollback_changes!

      {
        success: false,
        error: e.message,
        business_id: @business.id,
        domain: @business.hostname
      }
    end
  end

  # Restart monitoring for a business (manual retry)
  # @return [Hash] Result with success status
  def restart_monitoring!
    Rails.logger.info "[CnameSetupService] Restarting monitoring for #{@business.hostname}"

    begin
      validate_business_for_restart!

      # Reset monitoring state
      @business.update!(
        status: 'cname_monitoring',
        cname_monitoring_active: true,
        cname_check_attempts: 0
      )

      # Send restart notification email
      send_monitoring_restarted_email!

      # Start monitoring job
      DomainMonitoringJob.perform_later(@business.id)

      Rails.logger.info "[CnameSetupService] Monitoring restarted for #{@business.hostname}"

      {
        success: true,
        message: 'Domain monitoring restarted successfully',
        business_id: @business.id,
        domain: @business.hostname
      }

    rescue => e
      Rails.logger.error "[CnameSetupService] Failed to restart monitoring: #{e.message}"
      
      {
        success: false,
        error: e.message,
        business_id: @business.id,
        domain: @business.hostname
      }
    end
  end

  # Force activate domain (admin override)
  # @return [Hash] Result with success status
  def force_activate!
    Rails.logger.info "[CnameSetupService] Force activating domain for #{@business.hostname}"

    begin
      validate_business_exists!

      @business.update!(
        status: 'cname_active',
        cname_monitoring_active: false
      )

      # Send activation success email
      send_activation_success_email!

      Rails.logger.info "[CnameSetupService] Domain force activated for #{@business.hostname}"

      {
        success: true,
        message: 'Domain activated successfully',
        business_id: @business.id,
        domain: @business.hostname,
        status: @business.status
      }

    rescue => e
      Rails.logger.error "[CnameSetupService] Failed to force activate: #{e.message}"
      
      {
        success: false,
        error: e.message,
        business_id: @business.id,
        domain: @business.hostname
      }
    end
  end

  # Get current setup status for a business
  # @return [Hash] Detailed status information
  def status
    {
      business_id: @business.id,
      domain: @business.hostname,
      status: @business.status,
      monitoring_active: @business.cname_monitoring_active?,
      check_attempts: @business.cname_check_attempts,
      setup_email_sent: @business.cname_setup_email_sent_at.present?,
      render_domain_added: @business.render_domain_added?,
      can_setup: @business.can_setup_custom_domain?,
      can_restart: can_restart_monitoring?,
      created_at: @business.created_at,
      updated_at: @business.updated_at
    }
  end

  private

  def validate_business_eligibility!
    validate_business_exists!

    unless @business.host_type_custom_domain?
      raise InvalidBusinessError, 'Business must be configured for custom domain hosting'
    end

    if @business.cname_active?
      raise DomainAlreadyExistsError, 'Custom domain is already active'
    end

    if @business.hostname.blank?
      raise InvalidBusinessError, 'Business hostname is not configured'
    end
  end

  def validate_business_for_restart!
    validate_business_exists!

    unless ['cname_pending', 'cname_monitoring', 'cname_timeout'].include?(@business.status)
      raise InvalidBusinessError, 'Domain monitoring can only be restarted from pending, monitoring, or timeout status'
    end
  end

  def validate_business_exists!
    raise InvalidBusinessError, 'Business not found' if @business.nil?
  end

  # Determine which domain to add to Render based on canonical preference
  # Render will automatically handle redirects from the non-canonical version
  def determine_domains_to_add
    apex_domain = @business.hostname.sub(/^www\./, '')
    www_domain = "www.#{apex_domain}"
    
    case @business.canonical_preference
    when 'www'
      # Add www domain as primary - Render will redirect apex → www
      Rails.logger.info "[CnameSetupService] WWW canonical: adding www domain as primary"
      [www_domain]
    when 'apex'  
      # Add apex domain as primary - Render will redirect www → apex
      Rails.logger.info "[CnameSetupService] Apex canonical: adding apex domain as primary"
      [apex_domain]
    else
      # Fallback: add stored hostname as-is
      Rails.logger.warn "[CnameSetupService] Unknown canonical preference: #{@business.canonical_preference}, using stored hostname"
      [@business.hostname]
    end
  end

  def add_domain_to_render!
    Rails.logger.info "[CnameSetupService] Adding domain to Render: #{@business.hostname}"
    Rails.logger.info "[CnameSetupService] Canonical preference: #{@business.canonical_preference}"

    # Determine which domains to add based on canonical preference
    domains_to_add = determine_domains_to_add
    
    domains_to_add.each do |domain_name|
      # Check if domain already exists
      existing_domain = render_service.find_domain_by_name(domain_name)
      if existing_domain
        Rails.logger.info "[CnameSetupService] Domain already exists in Render: #{domain_name}"
        next
      end

      # Add new domain
      Rails.logger.info "[CnameSetupService] Adding domain to Render: #{domain_name}"
      domain_data = render_service.add_domain(domain_name)
      Rails.logger.info "[CnameSetupService] Domain added to Render successfully: #{domain_name} (#{domain_data['id']})"
    end
    
    @business.update!(render_domain_added: true)
  end

  def verify_render_domains!
    Rails.logger.info "[CnameSetupService] Triggering verification for domains added to Render"

    begin
      # Verify both canonical and sibling domains (apex + www). Render may have
      # created the sibling automatically and it will remain in "Needs
      # Verification" until verified once. Verifying both avoids manual steps in
      # the Render dashboard when switching canonical preference.
      apex_domain = @business.hostname.sub(/^www\./, '')
      domains_to_verify = [apex_domain, "www.#{apex_domain}"]
      
      domains_to_verify.each_with_index do |domain_name, index|
        # Add 30-second delay between apex and www verification to prevent Render certificate race
        wait_time = index == 0 ? 30.seconds : 60.seconds # apex at 30s, www at 60s
        Rails.logger.info "[CnameSetupService] Enqueuing async verification for #{domain_name} in #{wait_time} seconds"
        RenderDomainVerificationJob.set(wait: wait_time).perform_later(domain_name)
      end
    rescue => e
      # Don't fail the entire setup process if verification fails
      Rails.logger.error "[CnameSetupService] Error during domain verification: #{e.message}"
    end
  end

  def update_business_status!
    @business.update!(
      status: 'cname_pending',
      cname_monitoring_active: false,
      cname_check_attempts: 0
    )
  end

  def send_setup_instructions!
    Rails.logger.info "[CnameSetupService] Sending setup instructions email"

    # Find business owner/admin user
    owner = @business.users.where(role: 'manager').first

    if owner
      if deliver_domain_mail!(:setup_instructions, owner)
        @business.update!(cname_setup_email_sent_at: Time.current)
      else
        # deliver_domain_mail! rescued an ArgumentError from DomainMailer
        # (typically the Caddy "public IP not configured" guard, but
        # DomainMailer can also raise for other guard failures, e.g. a
        # blank business subdomain — see Bugbot LOW "Setup masks mail
        # ArgumentError cause"). Unlike restart_monitoring! /
        # force_activate! — where the business has already transitioned
        # to its target state and logging is the right degraded path —
        # start_setup! has NOT enabled monitoring or notified the
        # customer yet. Bubble the *actual* cause so the surrounding
        # rescue runs rollback_changes! and the JSON error reflects the
        # real problem instead of always blaming the public IP.
        cause = @last_mailer_error_message.presence || 'unknown DomainMailer guard failure'
        raise SetupError, "Setup instructions email could not be sent: #{cause}"
      end
    else
      Rails.logger.warn "[CnameSetupService] No owner found for business #{@business.id}, skipping email"
    end
  end

  # Provider-aware next-step copy returned by start_setup!. On Render the
  # canonical record for the www variant is a CNAME → bizblasts.onrender.com,
  # but on the Caddy self-hosted deployment customers configure A records for
  # BOTH apex and www pointing at BIZBLASTS_PUBLIC_IP, so hard-coding "CNAME"
  # contradicts the mailer / FAQ / DualDomainVerifier copy (Bugbot LOW:
  # "Setup API still says CNAME").
  def setup_next_steps
    if defined?(DomainProvider) && DomainProvider.caddy?
      [
        'Check your email for DNS setup instructions',
        'Add A records for both the apex (@) and www subdomain pointing at the BizBlasts server IP with your domain registrar',
        'We will monitor DNS propagation and notify you when complete'
      ]
    else
      [
        'Check your email for CNAME setup instructions',
        'Add the CNAME record with your domain registrar',
        'We will monitor DNS propagation and notify you when complete'
      ]
    end
  end

  def send_monitoring_restarted_email!
    owner = @business.users.where(role: 'manager').first
    deliver_domain_mail!(:monitoring_restarted, owner) if owner
  end

  def send_activation_success_email!
    owner = @business.users.where(role: 'manager').first
    deliver_domain_mail!(:activation_success, owner) if owner
  end

  # DomainMailer raises ArgumentError when one of its guards trips — most
  # commonly the Caddy "public IP not configured" check, but the mailer
  # also raises for other invariants (e.g. a blank business subdomain).
  # Callers like restart_monitoring! / force_activate! have already
  # persisted state transitions by the time we get here, so swallow the
  # exception with a loud log instead of leaving the business in
  # cname_monitoring with no email (Bugbot MEDIUM: "Restart leaves
  # monitoring without job"). Returns true on success, false on the
  # misconfiguration path. The raw exception message is stashed in
  # @last_mailer_error_message so start_setup!'s rollback can include
  # the real cause in its error response (Bugbot LOW: "Setup masks mail
  # ArgumentError cause").
  def deliver_domain_mail!(action, owner)
    @last_mailer_error_message = nil
    DomainMailer.public_send(action, @business, owner).deliver_now
    true
  rescue ArgumentError => e
    @last_mailer_error_message = e.message
    Rails.logger.error "[CnameSetupService] Skipping #{action} email for business #{@business.id}: #{e.message}"
    false
  end

  def start_monitoring!
    Rails.logger.info "[CnameSetupService] Starting DNS monitoring"
    
    @business.start_cname_monitoring!
    
    # Queue the monitoring job to start in 1 minute (give time for email to be read)
    DomainMonitoringJob.set(wait: 1.minute).perform_later(@business.id)
  end

  def can_restart_monitoring?
    ['cname_pending', 'cname_monitoring', 'cname_timeout'].include?(@business.status) &&
    @business.host_type_custom_domain?
  end

  def rollback_changes!
    Rails.logger.info "[CnameSetupService] Rolling back changes"
    
    # Check if domain was added to Render before updating the flag
    domain_was_added = @business.render_domain_added?
    
    # Reset business status
    @business.update!(
      status: 'active',
      cname_monitoring_active: false,
      cname_check_attempts: 0,
      render_domain_added: false
    )

    # Try to remove domain from Render if it was added
    if domain_was_added
      begin
        existing_domain = render_service.find_domain_by_name(@business.hostname)
        if existing_domain
          render_service.remove_domain(existing_domain['id'])
        end
      rescue => e
        Rails.logger.warn "[CnameSetupService] Failed to remove domain during rollback: #{e.message}"
      end
    end
  rescue => e
    Rails.logger.error "[CnameSetupService] Rollback failed: #{e.message}"
  end
end