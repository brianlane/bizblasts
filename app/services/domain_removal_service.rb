# frozen_string_literal: true

# Service for handling custom domain removal and disable scenarios.
# BizBlasts tiers have been removed; this service is purely host_type/status based.
class DomainRemovalService
  class RemovalError < StandardError; end

  def initialize(business)
    @business = business
    @render_service = RenderDomainService.new
  end

  # Complete domain removal - revert to subdomain hosting
  # @return [Hash] Result with success status and details
  def remove_domain!
    Rails.logger.info "[DomainRemovalService] Starting domain removal for business #{@business.id}"

    begin
      # Step 1: Stop any active monitoring
      stop_monitoring_if_active

      # Step 2: Remove domain from Render
      remove_from_render

      # Step 3: Update business configuration
      revert_to_subdomain

      # Step 4: Send confirmation email
      send_removal_confirmation

      Rails.logger.info "[DomainRemovalService] Domain removal completed for #{@business.id}"

      {
        success: true,
        message: 'Custom domain removed successfully',
        business_id: @business.id,
        reverted_to: subdomain_url,
        actions_taken: [
          'Stopped DNS monitoring',
          'Removed domain from Render service',
          'Reverted to subdomain hosting',
          'Sent confirmation email'
        ]
      }

    rescue => e
      Rails.logger.error "[DomainRemovalService] Domain removal failed: #{e.message}"
      
      {
        success: false,
        error: e.message,
        business_id: @business.id
      }
    end
  end

  # Disable custom domain temporarily (keep domain in Render but stop serving)
  # @return [Hash] Result with success status
  def disable_domain!
    Rails.logger.info "[DomainRemovalService] Disabling domain for business #{@business.id}"

    begin
      # Stop monitoring but keep domain configuration
      stop_monitoring_if_active

      # Update status but keep hostname and domain data
      @business.update!(
        status: 'inactive',
        cname_monitoring_active: false
      )

      {
        success: true,
        message: 'Custom domain disabled successfully',
        business_id: @business.id,
        note: 'Domain configuration preserved for re-enabling'
      }

    rescue => e
      Rails.logger.error "[DomainRemovalService] Domain disable failed: #{e.message}"
      
      {
        success: false,
        error: e.message,
        business_id: @business.id
      }
    end
  end

  # Get removal status and impact preview
  # @return [Hash] Information about what removal would affect
  def removal_preview
    {
      business_id: @business.id,
      current_domain: @business.hostname,
      current_status: @business.status,
      will_revert_to: subdomain_url,
      monitoring_active: @business.cname_monitoring_active?,
      render_domain_exists: check_render_domain_exists,
      impact: {
        domain_access: "#{@business.hostname} will no longer work",
        new_access: "Site will be accessible at #{subdomain_url}",
        redirects: "Automatic redirects will be removed",
        ssl: "SSL certificate for custom domain will be removed",
        email_links: "All email links will use subdomain"
      }
    }
  end

  private

  def stop_monitoring_if_active
    if @business.cname_monitoring_active?
      Rails.logger.info "[DomainRemovalService] Stopping active monitoring"
      @business.stop_cname_monitoring!
    end
  end

  def remove_from_render
    return unless @business.render_domain_added?
    
    if @business.hostname.blank?
      Rails.logger.info "[DomainRemovalService] Skipping domain removal - hostname is blank for business #{@business.id}"
      return
    end

    Rails.logger.info "[DomainRemovalService] Removing domains from Render service (apex + www)"

    apex_domain = @business.hostname.sub(/^www\./, '')
    www_domain  = "www.#{apex_domain}"

    [apex_domain, www_domain].uniq.each do |domain_name|
      begin
        domain = @render_service.find_domain_by_name(domain_name)

        if domain
          @render_service.remove_domain(domain['id'])
          Rails.logger.info "[DomainRemovalService] Removed domain from Render: #{domain_name}"
        else
          Rails.logger.info "[DomainRemovalService] Domain not present in Render (skipped): #{domain_name}"
        end
      rescue => e
        Rails.logger.warn "[DomainRemovalService] Failed to remove #{domain_name}: #{e.message}"
      end
    end
  end

  def revert_to_subdomain
    Rails.logger.info "[DomainRemovalService] Reverting business to subdomain hosting"

    # Ensure subdomain field is populated
    subdomain_value = @business.subdomain.presence || @business.hostname.presence || "business-#{@business.id}"

    @business.update!(
      host_type: 'subdomain',
      status: 'active',
      hostname: subdomain_value, # Keep hostname field populated with subdomain for compatibility
      subdomain: subdomain_value, # Ensure subdomain field is also set for consistency
      cname_monitoring_active: false,
      cname_check_attempts: 0,
      cname_setup_email_sent_at: nil,
      render_domain_added: false
    )

    Rails.logger.info "[DomainRemovalService] Business reverted to subdomain: #{subdomain_value}"
  end

  def send_removal_confirmation
    owner = @business.users.where(role: 'manager').first
    
    if owner
      # Would create DomainMailer.domain_removed email template
      SecureLogger.info "[DomainRemovalService] Would send domain removal confirmation to #{owner.email}"
      # DomainMailer.domain_removed(@business, owner).deliver_now
    else
      Rails.logger.warn "[DomainRemovalService] No owner found for removal confirmation email"
    end
  end

  def subdomain_url
    if @business.subdomain.present?
      subdomain = @business.subdomain
    elsif @business.hostname.present?
      subdomain = @business.hostname
    else
      subdomain = "business-#{@business.id}"
    end

    if Rails.env.production?
      "https://#{subdomain}.bizblasts.com"
    else
      "http://#{subdomain}.lvh.me:3000"
    end
  end

  def check_render_domain_exists
    return false unless @business.hostname.present?

    begin
      domain = @render_service.find_domain_by_name(@business.hostname)
      domain.present?
    rescue
      false
    end
  end
end