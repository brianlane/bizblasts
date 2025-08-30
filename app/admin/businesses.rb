# frozen_string_literal: true

ActiveAdmin.register Business do
  # Use numeric ID in action-item links to avoid hostname-with-dot issues
  config.clear_action_items!

  action_item :edit, only: :show do
    link_to 'Edit Business', edit_admin_business_path(resource.id)
  end

  action_item :delete, only: :show do
    link_to 'Delete Business', admin_business_path(resource.id), method: :delete, data: { confirm: 'Are you sure?' }
  end

  action_item :start_domain_setup, only: :show, if: proc { resource.can_setup_custom_domain? } do
    link_to 'Start Domain Setup', start_domain_setup_admin_business_path(resource.id),
           method: :post,
           data: { confirm: 'Begin CNAME setup and email instructions?' },
           class: 'button'
  end

  action_item :restart_domain_monitoring, only: :show, if: proc { ['cname_pending', 'cname_monitoring', 'cname_timeout'].include?(resource.status) } do
    link_to 'Restart Monitoring', restart_domain_monitoring_admin_business_path(resource.id),
           method: :post,
           data: { confirm: 'Restart DNS monitoring for another hour?' },
           class: 'button'
  end

  action_item :force_activate_domain, only: :show, if: proc { resource.premium_tier? && resource.host_type_custom_domain? } do
    link_to 'Force Activate Domain', force_activate_domain_admin_business_path(resource.id),
           method: :post,
           data: { confirm: 'Force-activate domain (bypasses DNS verification). Continue?' },
           class: 'button'
  end

  action_item :disable_custom_domain, only: :show, if: proc { resource.cname_active? || resource.status.in?(['cname_pending','cname_monitoring','cname_timeout']) } do
    link_to 'Remove Custom Domain', disable_custom_domain_admin_business_path(resource.id),
           method: :post,
           data: { confirm: 'Permanently remove custom domain and revert to subdomain hosting?' },
           class: 'button button-danger'
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
                :active, :tier, :subdomain, :service_template_id, 
                :hostname, :host_type, # Added new fields
                :stripe_customer_id, # Stripe integration
                :domain_coverage_applied, :domain_cost_covered, :domain_renewal_date, :domain_coverage_notes, # Domain coverage fields
                :domain_auto_renewal_enabled, :domain_coverage_expires_at, :domain_registrar, :domain_registration_date, # Auto-renewal tracking
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

  member_action :domain_status, method: :get do
    begin
      business = Business.find(params[:id])
      
      setup_service = CnameSetupService.new(business)
      status = setup_service.status
      
      # Add real-time DNS check if monitoring
      if business.cname_monitoring_active?
        dns_checker = CnameDnsChecker.new(business.hostname)
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
  filter :tier, as: :select, collection: Business.tiers.keys.map { |k| [k.humanize, k] }
  filter :industry
  filter :active
  filter :stripe_status, as: :select, collection: [['Connected', 'connected'], ['Not Connected', 'not_connected']], label: "Stripe Status"
  filter :domain_coverage_applied, as: :select, collection: [['Yes', true], ['No', false]]
  filter :cname_monitoring_active, as: :select, collection: [['Yes', true], ['No', false]]
  filter :domain_renewal_date
  filter :created_at

  # Index page configuration updated
  index do
    selectable_column
    column :id
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
        status_tag "Domain Active", class: "ok"
      when 'cname_timeout'
        status_tag "Setup Timeout", class: "error"
      else
        status_tag business.status.humanize, class: "default"
      end
    end
    column :tier
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
    column "Domain Coverage", :domain_coverage_applied do |business|
      if business.eligible_for_domain_coverage?
        if business.domain_coverage_applied?
          cost = business.domain_cost_covered || 0
          status_tag "Covered ($#{cost})", class: "ok"
        else
          status_tag "Available", class: "warning"
        end
      else
        status_tag "Not Eligible", class: "error"
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
      row :tier
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
        row "Connected At" do |business|
          # This would need to be tracked separately if needed
          "Not tracked"
        end
      end
    end
    
    # Domain Coverage Panel for Premium businesses
    if business.eligible_for_domain_coverage?
      panel "Domain Coverage Information" do
        attributes_table_for business do
          row "Coverage Status" do |business|
            if business.domain_coverage_applied?
              if business.domain_coverage_expired?
                status_tag "Coverage Expired", class: "error"
              elsif business.domain_coverage_expires_soon?
                status_tag "Expiring Soon (#{business.domain_coverage_remaining_days} days)", class: "warning"
              else
                status_tag "Coverage Applied", class: "ok"
              end
            else
              status_tag "Coverage Available", class: "warning"
            end
          end
          row "Coverage Limit" do |business|
            "$#{business.domain_coverage_limit}/year"
          end
          row "Amount Covered" do |business|
            business.domain_cost_covered.present? ? "$#{business.domain_cost_covered}" : "Not applied"
          end
          row "Domain Registrar" do |business|
            business.domain_registrar.present? ? business.domain_registrar.titleize : "Not specified"
          end
          row "Registration Date" do |business|
            business.domain_registration_date&.strftime("%B %d, %Y") || "Not set"
          end
          row "Domain Renewal Date" do |business|
            business.domain_renewal_date&.strftime("%B %d, %Y") || "Not set"
          end
          row "Coverage Expires" do |business|
            if business.domain_coverage_expires_at.present?
              expires_text = business.domain_coverage_expires_at.strftime("%B %d, %Y")
              if business.domain_coverage_expired?
                "#{expires_text} (EXPIRED)"
              elsif business.domain_coverage_expires_soon?
                "#{expires_text} (expires in #{business.domain_coverage_remaining_days} days)"
              else
                expires_text
              end
            else
              "Not set"
            end
          end
          row "Auto-Renewal Status" do |business|
            if business.domain_will_auto_renew?
              status_tag "Auto-Renewal Enabled", class: "ok"
            else
              status_tag "Manual Renewal", class: "warning"
            end
          end
          row "Coverage Notes" do |business|
            business.domain_coverage_notes.present? ? simple_format(business.domain_coverage_notes) : "No notes"
          end
        end
      end
    end
    
    # CNAME Custom Domain Panel for Premium businesses with custom domains
    if business.premium_tier? && business.host_type_custom_domain?
      panel "Custom Domain Management" do
        attributes_table_for business do
          row "Domain Status" do |business|
            case business.status
            when 'cname_pending'
              status_tag "Setup Pending", class: "warning"
            when 'cname_monitoring'
              status_tag "DNS Monitoring Active", class: "warning"
            when 'cname_active'
              status_tag "Active & Working", class: "ok"
            when 'cname_timeout'
              status_tag "Setup Timed Out", class: "error"
            else
              status_tag business.status.humanize, class: "default"
            end
          end
          row "Custom Domain" do |business|
            if business.hostname.present?
              if business.cname_active?
                link_to business.hostname, "https://#{business.hostname}", target: "_blank", class: "external-link"
              else
                business.hostname
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
        end
        
        # Live status refresh for monitoring domains
        if business.cname_monitoring_active?
          div id: "domain-live-status", style: "margin: 15px 0; padding: 10px; background: #f0f8ff; border-radius: 4px;" do
            p style: "margin: 0; font-weight: bold;" do
              "🔄 Live DNS Status: "
              span "Checking...", id: "live-status-text"
            end
            p style: "margin: 5px 0 0 0; font-size: 12px; color: #666;" do
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
          
          if business.premium_tier? && business.host_type_custom_domain?
            link_to "Force Activate Domain", force_activate_domain_admin_business_path(business.id), 
                    method: :post, class: "button", 
                    data: { confirm: "This will bypass DNS verification and immediately activate the domain. Use only if DNS is properly configured. Continue?" }
          end
          
          if business.cname_active? || business.status.in?(['cname_pending', 'cname_monitoring', 'cname_timeout'])
            link_to "Remove Custom Domain", disable_custom_domain_admin_business_path(business.id), 
                    method: :post, class: "button button-danger", style: "background-color: #dc3545; color: white;",
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
      f.input :name
      f.input :subdomain
      f.input :hostname
      f.input :host_type, as: :select, collection: Business.host_types.keys.map { |k| [k.humanize, k] }, include_blank: false
      f.input :tier, as: :select, collection: Business.tiers.keys.map { |k| [k.humanize, k] }, include_blank: false
      f.input :industry, as: :select, collection: Business.industries.keys.map { |k| [k.humanize, k] }, include_blank: false
      f.input :phone
      f.input :email
      f.input :website
      f.input :address
      f.input :city
      f.input :state
      f.input :zip
      f.input :description, as: :text
      f.input :time_zone, as: :select, collection: ActiveSupport::TimeZone.all.map { |tz| [tz.to_s, tz.name] }
      f.input :active
      f.input :service_template # Assuming this is the correct association name
    end
    
    # Stripe Integration section
    f.inputs "Stripe Integration" do
      f.input :stripe_account_id, label: "Stripe Connect Account ID", hint: "The Stripe Connect account ID for accepting payments (automatically set when connected)"
      f.input :stripe_customer_id, label: "Stripe Customer ID", hint: "The Stripe customer ID for business subscriptions (automatically set when paying for plans)"
    end
    
    # Domain Coverage section (only for Premium tier businesses)
    f.inputs "Domain Coverage (Premium Only)", class: "domain-coverage-section" do
      f.input :domain_coverage_applied, as: :boolean, label: "Domain coverage has been applied"
      f.input :domain_cost_covered, as: :number, step: 0.01, label: "Amount covered (USD)", hint: "Maximum $20.00/year"
      f.input :domain_registrar, as: :select, collection: [['Namecheap', 'namecheap'], ['GoDaddy', 'godaddy'], ['Cloudflare', 'cloudflare'], ['Other', 'other']], include_blank: "Select registrar", label: "Domain registrar"
      f.input :domain_registration_date, as: :datepicker, label: "Domain registration date"
      f.input :domain_renewal_date, as: :datepicker, label: "Domain renewal date"
      f.input :domain_coverage_expires_at, as: :datepicker, label: "Coverage expires on", hint: "When BizBlasts coverage ends (usually 1 year from registration)"
      f.input :domain_auto_renewal_enabled, as: :boolean, label: "Auto-renewal enabled at registrar"
      f.input :domain_coverage_notes, as: :text, label: "Coverage notes", 
              hint: "Internal notes about domain coverage, cost details, alternatives offered, registrar info, etc."
    end
    
    f.actions
  end
end
