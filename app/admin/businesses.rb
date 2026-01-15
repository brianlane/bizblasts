# frozen_string_literal: true

ActiveAdmin.register Business do
  # Use numeric ID in action-item links to avoid hostname-with-dot issues
  config.clear_action_items!

  # Action item for creating new business (index page)
  action_item :new, only: :index do
    link_to 'New Business', new_admin_business_path, class: 'button'
  end

  action_item :edit, only: :show do
    link_to 'Edit Business', edit_admin_business_path(resource.id)
  end

  action_item :delete, only: :show do
    link_to 'Delete Business', admin_business_path(resource.id), method: :delete, data: { confirm: 'Are you sure?' }
  end

  action_item :start_domain_setup, only: :show, if: proc { resource.can_setup_custom_domain? } do
    link_to 'Start Domain Setup', start_domain_setup_admin_business_path(resource.id),
            class: 'button aa-post-confirm',
            data: { turbo: false, confirm: 'Begin CNAME setup and email instructions?' }
  end

  action_item :restart_domain_monitoring, only: :show, if: proc { ['cname_pending', 'cname_monitoring', 'cname_timeout'].include?(resource.status) } do
    link_to 'Restart Monitoring', restart_domain_monitoring_admin_business_path(resource.id),
            class: 'button aa-post-confirm',
            data: { turbo: false, confirm: 'Restart DNS monitoring for another hour?' }
  end

  action_item :send_stripe_connect_reminder, only: :show do
    needs_reminder = resource.stripe_account_id.blank?

    unless needs_reminder
      begin
        needs_reminder = !StripeService.check_onboarding_status(resource)
      rescue => e
        Rails.logger.warn "[ADMIN] Unable to verify Stripe onboarding status for business #{resource.id}: #{e.message}"
        needs_reminder = true
      end
    end

    if needs_reminder
      link_to 'Send Stripe Connect Reminder',
              send_stripe_connect_reminder_admin_business_path(resource.id),
              class: 'button aa-post-confirm',
              data: {
                turbo: false,
                confirm: 'Send a magic-link email prompting this business to finish connecting Stripe?'
              }
    end
  end

  action_item :force_activate_domain, only: :show, if: proc { resource.host_type_custom_domain? } do
    link_to 'Force Activate Domain', force_activate_domain_admin_business_path(resource.id),
            class: 'button aa-post-confirm',
            data: { turbo: false, confirm: 'Force-activate domain (bypasses DNS verification). Continue?' }
  end

  action_item :disable_custom_domain, only: :show, if: proc { resource.cname_active? || resource.status.in?(['cname_pending','cname_monitoring','cname_timeout']) } do
    link_to 'Remove Custom Domain', disable_custom_domain_admin_business_path(resource.id),
            class: 'button aa-post-confirm',
            data: { turbo: false, confirm: 'Permanently remove custom domain and revert to subdomain hosting?' }
  end

  # Remove tenant scoping for admin panel
  controller do
    # skip_before_action :set_tenant, if: -> { true } # REMOVED: Global filter was removed
    
    # Override finding resource logic to handle ID or hostname
    def find_resource
      # Check if the param looks like an ID (all digits) or a hostname
      if params[:id].match?(/\A\d+\z/)
        scoped_collection.find(params[:id]) # Find by primary key ID
      else
        # Attempt to find by hostname, raise NotFound if nil to match find() behavior
        scoped_collection.find_by!(hostname: params[:id]) 
      end
    rescue ActiveRecord::RecordNotFound
      # Handle cases where neither ID nor hostname matches
      raise ActiveRecord::RecordNotFound, "Couldn't find Business with 'id'=#{params[:id]} or 'hostname'=#{params[:id]}"
    end

    # Ensure redirects after create/update use numeric ID to avoid dots in hostname.
    def create
      super do |success, _failure|
        success.html { return redirect_to admin_business_path(resource.id) }
      end
    end

    def update
      super do |success, _failure|
        success.html { return redirect_to admin_business_path(resource.id) }
      end
    end

    # Ensure form actions use numeric ID instead of business.to_param (hostname)
    def resource_path(resource)
      admin_business_path(resource.id)
    end

    def resource_url(resource)
      admin_business_url(resource.id)
    end
  end

  # Permit parameters updated for hostname/host_type, domain coverage, and CNAME fields
  permit_params :name, :industry, :phone, :email, :website,
                :address, :city, :state, :zip, :description, :time_zone,
                :active, :subdomain, :service_template_id,
                :hostname, :host_type, :canonical_preference, # Added new fields
                :website_layout, :enhanced_accent_color, # Website layout customization
                :stripe_customer_id, :platform_fee_percentage, # Stripe integration
                :status, :cname_setup_email_sent_at, :cname_monitoring_active, :cname_check_attempts, :render_domain_added # CNAME fields

  # Enable batch actions
  batch_action :destroy, confirm: "Are you sure you want to delete these businesses?" do |ids|
    deleted_count = 0
    failed_count = 0
    
    Business.where(id: ids).find_each do |business|
      begin
        business.destroy!
        deleted_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to delete business #{business.id}: #{e.message}"
      end
    end
    
    if failed_count > 0
      redirect_to collection_path, alert: "#{deleted_count} businesses deleted successfully. #{failed_count} businesses failed to delete."
    else
      redirect_to collection_path, notice: "#{deleted_count} businesses deleted successfully."
    end
  end

  batch_action :activate, confirm: "Are you sure you want to activate these businesses?" do |ids|
    updated_count = 0
    failed_count = 0
    
    Business.where(id: ids).find_each do |business|
      begin
        business.update!(active: true)
        updated_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to activate business #{business.id}: #{e.message}"
      end
    end
    
    if failed_count > 0
      redirect_to collection_path, alert: "#{updated_count} businesses activated successfully. #{failed_count} businesses failed to activate."
    else
      redirect_to collection_path, notice: "#{updated_count} businesses activated successfully."
    end
  end

  batch_action :deactivate, confirm: "Are you sure you want to deactivate these businesses?" do |ids|
    updated_count = 0
    failed_count = 0
    
    Business.where(id: ids).find_each do |business|
      begin
        business.update!(active: false)
        updated_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to deactivate business #{business.id}: #{e.message}"
      end
    end
    
    if failed_count > 0
      redirect_to collection_path, alert: "#{updated_count} businesses deactivated successfully. #{failed_count} businesses failed to deactivate."
    else
      redirect_to collection_path, notice: "#{updated_count} businesses deactivated successfully."
    end
  end

  # CNAME Domain Management Actions
  member_action :start_domain_setup, method: :post do
    begin
      setup_service = CnameSetupService.new(resource)
      result = setup_service.start_setup!
      
      if result[:success]
        redirect_to admin_business_path(resource.id), notice: result[:message]
      else
        redirect_to admin_business_path(resource.id), alert: "Domain setup failed: #{result[:error]}"
      end
    rescue => e
      redirect_to admin_business_path(resource.id), alert: "Error starting domain setup: #{e.message}"
    end
  end

  member_action :restart_domain_monitoring, method: :post do
    begin
      setup_service = CnameSetupService.new(resource)
      result = setup_service.restart_monitoring!
      
      if result[:success]
        redirect_to admin_business_path(resource.id), notice: result[:message]
      else
        redirect_to admin_business_path(resource.id), alert: "Failed to restart monitoring: #{result[:error]}"
      end
    rescue => e
      redirect_to admin_business_path(resource.id), alert: "Error restarting monitoring: #{e.message}"
    end
  end

  member_action :force_activate_domain, method: :post do
    begin
      setup_service = CnameSetupService.new(resource)
      result = setup_service.force_activate!
      
      if result[:success]
        redirect_to admin_business_path(resource.id), notice: result[:message]
      else
        redirect_to admin_business_path(resource.id), alert: "Failed to activate domain: #{result[:error]}"
      end
    rescue => e
      redirect_to admin_business_path(resource.id), alert: "Error activating domain: #{e.message}"
    end
  end

  member_action :disable_custom_domain, method: :post do
    begin
      removal_service = DomainRemovalService.new(resource)
      result = removal_service.remove_domain!
      
      if result[:success]
        redirect_to admin_business_path(resource.id), notice: result[:message]
      else
        redirect_to admin_business_path(resource.id), alert: "Failed to remove domain: #{result[:error]}"
      end
    rescue => e
      redirect_to admin_business_path(resource.id), alert: "Error removing domain: #{e.message}"
    end
  end

  member_action :send_stripe_connect_reminder, method: :post do
    business = Business.find(params[:id])
    user = business.users.where(role: [:manager]).first || business.users.where(role: [:staff]).first

    unless user
      redirect_to admin_business_path(business.id), alert: 'No business manager or staff user available to email.'
      return
    end

    created_connect_account = false

    if business.stripe_account_id.blank?
      begin
        StripeService.create_connect_account(business)
        created_connect_account = true
      rescue Stripe::StripeError => e
        Rails.logger.error "[ADMIN] Failed to create Stripe account for business #{business.id}: #{e.message}"
        redirect_to admin_business_path(business.id), alert: "Could not create Stripe account: #{e.message}"
        return
      rescue => e
        Rails.logger.error "[ADMIN] Unexpected error creating Stripe account for business #{business.id}: #{e.message}"
        redirect_to admin_business_path(business.id), alert: 'Unexpected error while creating Stripe account.'
        return
      end
    end

    mail = BusinessMailer.stripe_connect_reminder(user, business)

    unless mail
      message = 'Unable to generate reminder email. Verify the user can receive system emails.'
      redirect_to admin_business_path(business.id), alert: message
      return
    end

    mail.deliver_later
    business.update!(stripe_connect_reminder_sent_at: Time.current)

    notice_message = 'Stripe connect reminder email queued for delivery.'
    notice_message += ' A new Stripe account was created to support onboarding.' if created_connect_account

    redirect_to admin_business_path(business.id), notice: notice_message
  end

  member_action :domain_status, method: :get do
    begin
      business = Business.find(params[:id])
      
      setup_service = CnameSetupService.new(business)
      status = setup_service.status
      
      # Add real-time DNS check if monitoring
      if business.cname_monitoring_active?
        # Use canonical domain for DNS checking instead of raw hostname
        check_domain = business.canonical_domain || business.hostname
        dns_checker = CnameDnsChecker.new(check_domain)
        dns_result = dns_checker.verify_cname
        status[:dns_check] = {
          verified: dns_result[:verified],
          target: dns_result[:target],
          checked_at: dns_result[:checked_at],
          error: dns_result[:error]
        }
      end
      
      render json: status
    rescue => e
      render json: { error: e.message }, status: :internal_server_error
    end
  end

  # Filter options updated
  filter :name
  filter :hostname
  filter :host_type, as: :select, collection: Business.host_types.keys.map { |k| [k.humanize, k] }
  filter :status, as: :select, collection: Business.statuses.keys.map { |k| [k.humanize, k] }
  filter :industry
  filter :active
  filter :stripe_status, as: :select, collection: [['Connected', 'connected'], ['Not Connected', 'not_connected']], label: "Stripe Status"
  filter :cname_monitoring_active, as: :select, collection: [['Yes', true], ['No', false]]
  filter :created_at

  # Index page configuration updated
  index do
    selectable_column
    column :id
    column 'Logo', :logo do |business|
      if business.logo.attached?
        begin
          image_tag business.logo.variant(resize_to_limit: [40, 40]),
                    class: "h-10 w-10 object-cover rounded-full",
                    alt: business.name || "Business Logo"
        rescue => e
          # Log the error for debugging
          Rails.logger.warn "[ADMIN] Logo variant failed for business #{business.id}: #{e.message}"

          # Show fallback avatar instead of breaking the page
          business_name = business.name.to_s.strip
          business_name = "Business" if business_name.blank?
          initials = business_name.split.map(&:first).join.upcase[0..1]

          content_tag :div,
                      initials,
                      class: "h-10 w-10 bg-red-200 text-red-800 rounded-full flex items-center justify-center text-xs font-medium",
                      title: "Logo processing error"
        end
      else
        # Fallback for businesses without logos
        business_name = business.name.to_s.strip
        business_name = "Business" if business_name.blank?
        initials = business_name.split.map(&:first).join.upcase[0..1]

        content_tag :div,
                    initials,
                    class: "h-10 w-10 bg-gray-300 text-gray-600 rounded-full flex items-center justify-center text-xs font-medium"
      end
    end
    column :name
    column :subdomain
    column :hostname
    column :host_type
    column :status do |business|
      case business.status
      when 'cname_pending'
        status_tag "Setup Pending", class: "warning"
      when 'cname_monitoring'
        status_tag "DNS Monitoring", class: "warning"
      when 'cname_active'
        # Use cached domain health data instead of external API calls
        if business.host_type_custom_domain? && business.hostname.present?
          if business.domain_health_verified?
            status_tag "Domain Active", class: "ok"
          else
            # Check if health data is stale (older than 1 hour)
            if business.domain_health_stale?
              status_tag "Domain Active (Stale)", class: "warning"
            else
              status_tag "SSL Provisioning", class: "warning"
            end
          end
        else
          status_tag "Domain Active", class: "ok"
        end
      when 'cname_timeout'
        status_tag "Setup Timeout", class: "error"
      else
        status_tag business.status.humanize, class: "default"
      end
    end
    column "Stripe Status", :stripe_account_id do |business|
      if business.stripe_account_id.present?
        begin
          if StripeService.check_onboarding_status(business)
            status_tag("Connected", class: "ok") + " (Account ID: #{business.stripe_account_id})".html_safe
          else
            status_tag("Setup Incomplete", class: "warning") + " (Account ID: #{business.stripe_account_id})".html_safe
          end
        rescue => e
          status_tag("Error", class: "error") + " (Account ID: #{business.stripe_account_id})".html_safe
        end
      else
        status_tag "Not Connected", class: "error"
      end
    end
    column :industry do |business|
      Business.industries[business.industry]
    end
    column :email
    column :active
    column :created_at
    # Explicitly define actions to ensure correct path generation
    actions defaults: false do |business|
      item "View", admin_business_path(business.id)
      item "Edit", edit_admin_business_path(business.id)
      item "Delete", admin_business_path(business.id), method: :delete, data: { confirm: "Are you sure?" }

      if business.can_setup_custom_domain?
        item "Start Domain Setup", start_domain_setup_admin_business_path(business.id), class: 'member_link aa-post-confirm', data: { turbo: false, confirm: 'Begin CNAME setup and email instructions?' }
      end

      if ['cname_pending', 'cname_monitoring', 'cname_timeout'].include?(business.status)
        item "Restart Monitoring", restart_domain_monitoring_admin_business_path(business.id), class: 'member_link aa-post-confirm', data: { turbo: false, confirm: 'Restart DNS monitoring for another hour?' }
      end

      if business.host_type_custom_domain?
        item "Force Activate Domain", force_activate_domain_admin_business_path(business.id), class: 'member_link aa-post-confirm', data: { turbo: false, confirm: 'Force-activate domain (bypasses DNS verification). Continue?' }
      end

      if business.cname_active? || business.status.in?(['cname_pending', 'cname_monitoring', 'cname_timeout'])
        item "Remove Custom Domain", disable_custom_domain_admin_business_path(business.id), class: 'member_link aa-post-confirm', data: { turbo: false, confirm: 'Permanently remove custom domain and revert to subdomain hosting?' }
      end
    end
  end

  # Show page configuration updated
  show do
    attributes_table do
      row :id
      row :name
      row :subdomain
      row :hostname
      row :host_type
      row :canonical_preference do |business|
        if business.host_type_custom_domain?
          status_tag(business.canonical_preference.humanize, class: business.www_canonical_preference? ? "ok" : "warning")
        else
          "N/A (Subdomain)"
        end
      end
      row "Stripe Status" do |business|
        if business.stripe_account_id.present?
          begin
            if StripeService.check_onboarding_status(business)
              status_tag("Connected", class: "ok") + " (Account ID: #{ERB::Util.h(business.stripe_account_id)})".html_safe
            else
              status_tag("Setup Incomplete", class: "warning") + " (Account ID: #{ERB::Util.h(business.stripe_account_id)})".html_safe
            end
          rescue => e
            status_tag("Error", class: "error") + " (Account ID: #{ERB::Util.h(business.stripe_account_id)})".html_safe
          end
        else
          status_tag "Not Connected", class: "error"
        end
      end
      row "Platform Fee (%)" do |business|
        business.platform_fee_percentage
      end
      row :industry do |business|
        Business.industries[business.industry]
      end
      row :phone
      row :email
      row :website
      row :address
      row :city
      row :state
      row :zip
      row :description
      row :time_zone
      row :active
      row :website_layout do |business|
        business.website_layout&.humanize
      end
      row :enhanced_accent_color do |business|
        if business.website_layout_enhanced?
          content_tag(:span, business.enhanced_accent_color&.humanize,
                      class: "accent-color-badge accent-#{business.enhanced_accent_color}",
                      style: "display: inline-block; padding: 4px 8px; border-radius: 3px; font-weight: bold; text-transform: capitalize;")
        else
          "N/A (Basic layout)"
        end
      end
      row :created_at
      row :updated_at
    end
    
    # Stripe Integration Panel
    panel "Stripe Integration" do
      attributes_table_for business do
        row "Connection Status" do |business|
          if business.stripe_account_id.present?
            begin
              if StripeService.check_onboarding_status(business)
                status_tag("Connected", class: "ok") + " (Account ID: #{ERB::Util.h(business.stripe_account_id)})".html_safe
              else
                status_tag("Setup Incomplete", class: "warning") + " (Account ID: #{ERB::Util.h(business.stripe_account_id)})".html_safe
              end
            rescue => e
              status_tag("Error", class: "error") + " (Account ID: #{ERB::Util.h(business.stripe_account_id)})".html_safe
            end
          else
            status_tag "Not Connected", class: "error"
          end
        end
        row "Stripe Connect Account ID" do |business|
          business.stripe_account_id.present? ? business.stripe_account_id : "Not set"
        end
        row "Stripe Customer ID (for subscriptions)" do |business|
          business.stripe_customer_id.present? ? business.stripe_customer_id : "Not set"
        end
        # Live diagnostics from Stripe for onboarding status
        row "Stripe Account Diagnostics" do |business|
          unless business.stripe_account_id.present?
            next "Not available (no Stripe account)"
          end

          # Placeholder that will be replaced asynchronously via JS to avoid blocking page render
          div id: "stripe-diagnostics", style: "white-space: pre-wrap;" do
            "Loading diagnostics "
          end

          script do
            raw <<-JS
              fetch('/admin/businesses/#{business.id}/stripe_diagnostics')
                .then(r => r.json())
                .then(data => {
                  const el = document.getElementById('stripe-diagnostics');
                  if (data.diagnostics) {
                    el.textContent = data.diagnostics;
                  } else {
                    el.textContent = data.error || 'Unable to fetch diagnostics';
                  }
                })
                .catch(() => {
                  const el = document.getElementById('stripe-diagnostics');
                  el.textContent = 'Error fetching diagnostics';
                });
            JS
          end
        end
        row "Connected At" do |business|
          # This would need to be tracked separately if needed
          "Not tracked"
        end
      end
    end
    
    # CNAME Custom Domain Panel for businesses with custom domains
    if business.host_type_custom_domain?
      panel "Custom Domain Management" do
        attributes_table_for business do
          # Perform single health check for both status rows (performance optimization)
          health_check_result = nil
          if business.status == 'cname_active' && business.hostname.present?
            begin
              check_domain = business.canonical_domain || business.hostname
              health_checker = DomainHealthChecker.new(check_domain)
              health_check_result = health_checker.check_health
            rescue => e
              Rails.logger.warn "[AdminPanel] Domain health check failed for #{business.hostname}: #{e.message}"
              health_check_result = { healthy: false, error: "Health check failed: #{e.message}" }
            end
          end
          
          row "Domain Status" do |business|
            case business.status
            when 'cname_pending'
              status_tag "Setup Pending", class: "warning"
            when 'cname_monitoring'
              status_tag "DNS Monitoring Active", class: "warning"
            when 'cname_active'
              # Use pre-computed health check result
              if health_check_result
                if health_check_result[:healthy] && health_check_result[:ssl_ready] == true
                  status_tag "Active & Working", class: "ok"
                elsif health_check_result[:healthy] && health_check_result[:ssl_ready] == false
                  status_tag "SSL Certificate Provisioning", class: "warning"
                elsif health_check_result[:error]&.include?("Certificate propagation")
                  status_tag "SSL Certificate Provisioning", class: "warning"
                elsif health_check_result[:healthy] && health_check_result[:ssl_ready].nil?
                  status_tag "Active (SSL Status Unknown)", class: "warning"
                elsif health_check_result[:healthy]
                  status_tag "Active (SSL Status Unknown)", class: "warning"
                else
                  # Fall back to cached data if health check fails
                  if business.domain_health_verified?
                    status_tag "Active & Working", class: "ok"
                  else
                    status_tag "SSL Certificate Provisioning", class: "warning"
                  end
                end
              else
                # No health check performed, use cached data
                if business.domain_health_verified?
                  status_tag "Active & Working", class: "ok"
                else
                  status_tag "SSL Certificate Provisioning", class: "warning"
                end
              end
            when 'cname_timeout'
              status_tag "Setup Timed Out", class: "error"
            else
              status_tag business.status.humanize, class: "default"
            end
          end
          row "Custom Domain" do |business|
            if business.hostname.present?
              # Use canonical domain for display and links
              canonical_domain = business.canonical_domain || business.hostname
              display_text = business.hostname
              # Show canonical preference indicator if different from hostname
              if canonical_domain != business.hostname
                display_text += " → #{canonical_domain}"
              end
              
              if business.cname_active?
                link_to display_text, "https://#{canonical_domain}", target: "_blank", class: "external-link"
              else
                display_text
              end
            else
              "Not configured"
            end
          end
          row "Monitoring Active" do |business|
            business.cname_monitoring_active? ? status_tag("Yes", class: "ok") : status_tag("No", class: "default")
          end
          row "DNS Check Attempts" do |business|
            "#{business.cname_check_attempts}/12"
          end
          row "Setup Email Sent" do |business|
            if business.cname_setup_email_sent_at.present?
              "#{time_ago_in_words(business.cname_setup_email_sent_at)} ago"
            else
              "Not sent"
            end
          end
          row "Render Domain Added" do |business|
            business.render_domain_added? ? status_tag("Yes", class: "ok") : status_tag("No", class: "error")
          end
          row "Domain Health Last Checked" do |business|
            if business.domain_health_checked_at.present?
              "#{time_ago_in_words(business.domain_health_checked_at)} ago"
            else
              "Never checked"
            end
          end
          row "SSL Certificate Status" do |business|
            if business.hostname.present? && health_check_result
              # Use pre-computed health check result (no duplicate API call)
              if health_check_result[:ssl_ready]
                status_tag "SSL Ready", class: "ok"
              elsif health_check_result[:error]&.include?("Certificate propagation")
                status_tag "Propagating (5-30 min)", class: "warning"
              elsif health_check_result[:healthy]
                status_tag "HTTP Only", class: "warning"
              elsif health_check_result[:error]
                status_tag "SSL Check Failed", class: "error"
              else
                status_tag "Status Unknown", class: "warning"
              end
            elsif business.hostname.present?
              # No health check was performed, use cached data
              if business.domain_health_verified?
                status_tag "Cached: SSL Verified", class: "ok"
              else
                status_tag "Cached: SSL Pending", class: "warning"
              end
            else
              "N/A"
            end
          end
        end
        
        # Live status refresh for monitoring domains
        if business.cname_monitoring_active?
          div id: "domain-live-status", style: "margin: 15px 0; padding: 10px; background: #f0f8ff; border-radius: 4px;" do
            para style: "margin: 0; font-weight: bold;" do
              "🔄 Live DNS Status: "
              span "Checking...", id: "live-status-text"
            end
            para style: "margin: 5px 0 0 0; font-size: 12px; color: #666;" do
              "Last checked: "
              span "Never", id: "last-checked"
            end
          end
          
          script do
            raw <<-JAVASCRIPT
              function updateDomainStatus() {
                fetch('/admin/businesses/#{business.id}/domain_status')
                  .then(response => response.json())
                  .then(data => {
                    const statusText = document.getElementById('live-status-text');
                    const lastChecked = document.getElementById('last-checked');
                    
                    if (data.dns_check) {
                      if (data.dns_check.verified) {
                        statusText.innerHTML = '✅ DNS Verified';
                        statusText.style.color = 'green';
                      } else {
                        statusText.innerHTML = '⏳ DNS Pending';
                        statusText.style.color = 'orange';
                      }
                      lastChecked.textContent = new Date(data.dns_check.checked_at).toLocaleTimeString();
                    } else {
                      statusText.innerHTML = '📊 Monitoring Active';
                      statusText.style.color = 'blue';
                    }
                  })
                  .catch(error => {
                    console.error('Error fetching domain status:', error);
                  });
              }
              
              // Update immediately and then every 30 seconds
              updateDomainStatus();
              setInterval(updateDomainStatus, 30000);
            JAVASCRIPT
          end
        end
        
        # Domain management actions
        div class: "domain-actions", style: "margin-top: 15px;" do
          if business.can_setup_custom_domain?
            link_to "Start Domain Setup", start_domain_setup_admin_business_path(business.id), 
                    method: :post, class: "button", 
                    data: { confirm: "This will start the CNAME setup process and send setup instructions via email. Continue?" }
          end
          
          if ['cname_pending', 'cname_monitoring', 'cname_timeout'].include?(business.status)
            link_to "Restart Monitoring", restart_domain_monitoring_admin_business_path(business.id), 
                    method: :post, class: "button", 
                    data: { confirm: "This will restart DNS monitoring for another hour. Continue?" }
          end
          
          if business.host_type_custom_domain?
            link_to "Force Activate Domain", force_activate_domain_admin_business_path(business.id), 
                    method: :post, class: "button", 
                    data: { confirm: "This will bypass DNS verification and immediately activate the domain. Use only if DNS is properly configured. Continue?" }
          end
          
          if business.cname_active? || business.status.in?(['cname_pending', 'cname_monitoring', 'cname_timeout'])
            button_to "Remove Custom Domain", disable_custom_domain_admin_business_path(business.id), 
                    method: :post, class: "button", style: "background-color: #dc3545; color: white;",
                    data: { confirm: "⚠️ WARNING: This will permanently remove the custom domain and revert to subdomain hosting (#{business.subdomain || business.hostname}.bizblasts.com). The domain will no longer work for this business. This action cannot be undone. Are you sure you want to continue?" }
          end
        end
      end
    end
    
    panel "Users" do
      table_for business.users do
        column :id
        column :email
        column :role do |user|
          user.role&.humanize
        end
        column :created_at
        column do |user|
          links = []
          links << link_to("View", admin_user_path(user))
          links.join(" | ").html_safe
        end
      end
    end
  end

  # Form configuration updated
  form do |f|
    f.inputs "Business Details" do
      f.input :name, hint: "Business name (used to auto-generate subdomain/hostname)"

      # Hosting type
      f.input :host_type, as: :select, collection: Business.host_types.keys.map { |k| [k.humanize, k] }, include_blank: false

      # Subdomain field
      f.input :subdomain,
              wrapper_html: { class: 'subdomain-field-wrapper' },
              hint: "Auto-generated from business name. Will appear as: <span class='subdomain-preview'></span>"

      # Hostname field (for custom domains)
      f.input :hostname,
              wrapper_html: { class: 'hostname-field-wrapper' },
              hint: "For custom domains (e.g., yourbusiness.com). Auto-generated but can be edited."

      f.input :industry, as: :select, collection: Business.industries.keys.map { |k| [k.humanize, k] }, include_blank: false
      f.input :email, hint: "Primary business email (used for manager login)"
      f.input :phone
      f.input :address
      f.input :city
      f.input :state, as: :select, collection: ['AL', 'AK', 'AZ', 'AR', 'CA', 'CO', 'CT', 'DE', 'FL', 'GA', 'HI', 'ID', 'IL', 'IN', 'IA', 'KS', 'KY', 'LA', 'ME', 'MD', 'MA', 'MI', 'MN', 'MS', 'MO', 'MT', 'NE', 'NV', 'NH', 'NJ', 'NM', 'NY', 'NC', 'ND', 'OH', 'OK', 'OR', 'PA', 'RI', 'SC', 'SD', 'TN', 'TX', 'UT', 'VT', 'VA', 'WA', 'WV', 'WI', 'WY']
      f.input :zip
    end

    # Advanced/Optional section (collapsible)
    f.inputs "Advanced Settings (Optional)", class: "advanced-settings" do
      f.input :description, as: :text, hint: "Optional - can be added later"
      f.input :website
      f.input :time_zone, as: :select, collection: ActiveSupport::TimeZone.all.map { |tz| [tz.to_s, tz.name] }, hint: "Auto-set from state if left blank"
      f.input :active, hint: "Uncheck to create business as inactive"
      f.input :canonical_preference, as: :select, collection: Business.canonical_preferences.keys.map { |k| [k.humanize, k] }, include_blank: false, hint: "For custom domains: www vs apex"
      f.input :service_template
    end

    # Stripe Integration section
    f.inputs "Stripe Integration (Optional)", class: "stripe-section" do
      f.input :stripe_account_id, label: "Stripe Connect Account ID", hint: "The Stripe Connect account ID for accepting payments (automatically set when connected)"
      f.input :stripe_customer_id, label: "Stripe Customer ID", hint: "Stripe customer identifier (rarely needed; typically managed by Stripe flows)"
      f.input :platform_fee_percentage,
              label: "Platform Fee (%)",
              hint: "Enter percent (0.5 = 0.5%, 1.0 = 1%, 50 = 50%) or fraction (0.01 = 1%). Range 0–100."
    end

    # Website Layout & Customization section
    f.inputs "Website Layout & Customization", class: "website-layout-section" do
      f.input :website_layout, as: :radio, collection: [
        ['Basic Layout', 'basic'],
        ['Enhanced Layout', 'enhanced']
      ], hint: "Choose the website layout style for this business. Enhanced layout provides modern design with customizable colors."

      f.input :enhanced_accent_color, as: :select,
              collection: [
                ['Red', 'red'],
                ['Orange', 'orange'],
                ['Amber', 'amber'],
                ['Emerald', 'emerald'],
                ['Sky', 'sky'],
                ['Violet', 'violet']
              ],
              include_blank: "Select accent color",
              wrapper_html: { class: 'enhanced-accent-color-wrapper hidden-by-default' },
              hint: "Choose the accent color theme for the enhanced layout (only applies when Enhanced Layout is selected)"
    end

    f.actions

    # Add JavaScript for dynamic field switching and subdomain generation
    script do
      raw <<-JS
          (function() {
            // Slugify function to convert business name to URL-safe subdomain
            function slugify(text) {
              return text.toString().toLowerCase()
                .trim()
                .replace(/\\s+/g, '-')           // Replace spaces with -
                .replace(/[^\\w\\-]+/g, '')       // Remove all non-word chars
                .replace(/\\-\\-+/g, '-')         // Replace multiple - with single -
                .replace(/^-+/, '')              // Trim - from start of text
                .replace(/-+$/, '');             // Trim - from end of text
            }

            // Update subdomain/hostname field visibility based on host_type
            function updateFieldsForHostType(hostType) {
              const subdomainWrapper = $('.subdomain-field-wrapper');
              const hostnameWrapper = $('.hostname-field-wrapper');
              const hostTypeField = $('#business_host_type');

              if (hostType === 'custom_domain') {
                subdomainWrapper.hide();
                hostnameWrapper.show();
                hostTypeField.val('custom_domain');
              } else {
                subdomainWrapper.show();
                hostnameWrapper.hide();
                hostTypeField.val('subdomain');
              }
            }

            // Auto-generate subdomain/hostname from business name
            function updateSlugFields() {
              const businessName = $('#business_name').val();
              const hostType = $('#business_host_type').val();
              const slug = slugify(businessName);

              if (hostType === 'custom_domain') {
                // Only auto-generate hostname if it's empty (new business)
                // Don't overwrite existing hostnames for businesses being edited
                const hostnameField = $('#business_hostname');
                if (!hostnameField.val() || hostnameField.val().trim() === '') {
                  hostnameField.val(slug + '.com');
                }
              } else {
                // Only auto-generate subdomain if it's empty (new business)
                const subdomainField = $('#business_subdomain');
                if (!subdomainField.val() || subdomainField.val().trim() === '') {
                  subdomainField.val(slug);
                }
                // Always update preview for subdomain
                $('.subdomain-preview').text(slug + '.bizblasts.com');
              }
            }

            // Show/hide enhanced_accent_color based on website_layout selection
            function updateLayoutFields() {
              const websiteLayout = $('input[name="business[website_layout]"]:checked').val();
              const accentColorWrapper = $('.enhanced-accent-color-wrapper');

              console.log('updateLayoutFields called');
              console.log('Selected layout:', websiteLayout);
              console.log('Found wrappers:', accentColorWrapper.length);

              if (websiteLayout === 'enhanced') {
                console.log('Showing accent color field');
                accentColorWrapper.removeClass('hidden-by-default');
              } else {
                console.log('Hiding accent color field');
                accentColorWrapper.addClass('hidden-by-default');
              }
            }

            // Initialize on page load
            $(document).ready(function() {
              console.log('Document ready - initializing layout fields');
              // Get initial host type value
              const initialHostType = $('#business_host_type').val() || 'subdomain';
              updateFieldsForHostType(initialHostType);

              // If there's a name, generate initial slug
              if ($('#business_name').val()) {
                updateSlugFields();
              }

              // Listen for host type changes
              $('#business_host_type').on('change', function() {
                const hostType = $(this).val();
                updateFieldsForHostType(hostType);
                updateSlugFields();
              });

              // Listen for name changes and auto-generate slug (debounced)
              let nameTimeout;
              $('#business_name').on('keyup', function() {
                clearTimeout(nameTimeout);
                nameTimeout = setTimeout(updateSlugFields, 300); // 300ms debounce
              });

              // Initialize website layout field visibility
              updateLayoutFields();

              // Listen for website layout changes
              $('input[name="business[website_layout]"]').on('change', function() {
                updateLayoutFields();
              });

              // Make advanced sections collapsible on initial load
              $('.advanced-settings, .stripe-section').addClass('collapsed');
              $('.advanced-settings legend, .stripe-section legend').css('cursor', 'pointer').on('click', function() {
                $(this).parent().toggleClass('collapsed');
              });
            });
          })();
      JS
    end

    # Add CSS styles for form customization
    content do
      raw <<-HTML
        <style>
          .subdomain-preview {
            font-weight: bold;
            color: #2a6496;
          }

          /* Hide accent color field by default, show when Enhanced layout selected */
          .hidden-by-default {
            display: none !important;
          }

          fieldset.collapsed > ol {
            display: none;
          }
          fieldset legend {
            cursor: pointer;
          }
          fieldset.collapsed legend:after {
            content: " ▶";
          }
          fieldset:not(.collapsed) legend:after {
            content: " ▼";
          }

          /* Accent color badges for show page */
          .accent-color-badge.accent-red {
            background-color: #ef4444;
            color: white;
          }
          .accent-color-badge.accent-orange {
            background-color: #f97316;
            color: white;
          }
          .accent-color-badge.accent-amber {
            background-color: #eab308;
            color: black;
          }
          .accent-color-badge.accent-emerald {
            background-color: #10b981;
            color: white;
          }
          .accent-color-badge.accent-sky {
            background-color: #0ea5e9;
            color: white;
          }
          .accent-color-badge.accent-violet {
            background-color: #a855f7;
            color: white;
          }
        </style>
      HTML
    end
  end

  # ---------------------------------------------------------------------------
  # After Create Callback: Auto-create Manager User & StaffMember
  # ---------------------------------------------------------------------------
  after_create do |business|
    # Create manager user with business email
    # Generate temporary secure password (user will reset via magic link)
    temp_password = SecureRandom.urlsafe_base64(16)

    user = User.create!(
      email: business.email,
      first_name: 'Business',
      last_name: 'Manager',
      role: :manager,
      business_id: business.id,
      password: temp_password,
      password_confirmation: temp_password
    )

    # Create staff member with default Mon-Fri 9am-5pm availability
    StaffMember.create!(
      business: business,
      user: user,
      name: user.full_name,
      email: user.email,
      active: true,
      availability: {
        'monday' => [{ 'start' => '09:00', 'end' => '17:00' }],
        'tuesday' => [{ 'start' => '09:00', 'end' => '17:00' }],
        'wednesday' => [{ 'start' => '09:00', 'end' => '17:00' }],
        'thursday' => [{ 'start' => '09:00', 'end' => '17:00' }],
        'friday' => [{ 'start' => '09:00', 'end' => '17:00' }],
        'saturday' => [],
        'sunday' => [],
        'exceptions' => {}
      }
    )
  end

  # ---------------------------------------------------------------------------
  # Async endpoint: Stripe Account Diagnostics
  # ---------------------------------------------------------------------------
  member_action :stripe_diagnostics, method: :get do
    begin
      unless resource.stripe_account_id.present?
        return render json: { error: 'No Stripe account connected' }, status: :unprocessable_content
      end

      StripeService.configure_stripe_api_key
      account = Stripe::Account.retrieve(resource.stripe_account_id)

      details = []
      details << "details_submitted: #{account.details_submitted}"
      details << "charges_enabled: #{account.charges_enabled}"
      details << "payouts_enabled: #{account.payouts_enabled}"

      disabled_reason = account.respond_to?(:requirements) ? (account.requirements&.disabled_reason || '-') : '-'
      currently_due   = account.respond_to?(:requirements) ? Array(account.requirements&.currently_due) : []
      past_due        = account.respond_to?(:requirements) ? Array(account.requirements&.past_due) : []

      details << "disabled_reason: #{disabled_reason}"
      details << "currently_due: #{currently_due.join(', ').presence || '-'}"
      details << "past_due: #{past_due.join(', ').presence || '-'}"

      render json: { diagnostics: details.join("\n") }
    rescue => e
      Rails.logger.error "[AdminPanel] Stripe diagnostics fetch failed for business #{resource.id}: #{e.message}"
      render json: { error: e.message }, status: :internal_server_error
    end
  end
end
