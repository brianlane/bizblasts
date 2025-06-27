# frozen_string_literal: true

ActiveAdmin.register Business do
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

    # Removed custom create action - let ActiveAdmin handle redirect
  end

  # Permit parameters updated for hostname/host_type and domain coverage
  permit_params :name, :industry, :phone, :email, :website,
                :address, :city, :state, :zip, :description, :time_zone,
                :active, :tier, :service_template_id, 
                :hostname, :host_type, # Added new fields
                :stripe_customer_id, # Stripe integration
                :domain_coverage_applied, :domain_cost_covered, :domain_renewal_date, :domain_coverage_notes, # Domain coverage fields
                :domain_auto_renewal_enabled, :domain_coverage_expires_at, :domain_registrar, :domain_registration_date # Auto-renewal tracking

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

  # Filter options updated
  filter :name
  filter :hostname
  filter :host_type, as: :select, collection: Business.host_types.keys.map { |k| [k.humanize, k] }
  filter :tier, as: :select, collection: Business.tiers.keys.map { |k| [k.humanize, k] }
  filter :industry
  filter :active
  filter :stripe_status, as: :select, collection: [['Connected', 'connected'], ['Not Connected', 'not_connected']], label: "Stripe Status"
  filter :domain_coverage_applied, as: :select, collection: [['Yes', true], ['No', false]]
  filter :domain_renewal_date
  filter :created_at

  # Index page configuration updated
  index do
    selectable_column
    column :id
    column :name
    column :hostname
    column :host_type
    column :tier
    column "Stripe Status", :stripe_account_id do |business|
      if business.stripe_account_id.present?
        begin
          if StripeService.check_onboarding_status(business)
            status_tag "Connected", class: "ok"
          else
            status_tag "Setup Incomplete", class: "warning"
          end
        rescue => e
          status_tag "Error", class: "error"
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
      row :hostname
      row :host_type
      row :tier
      row "Stripe Status" do |business|
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
        row "Connection Status" do |b|
          if b.stripe_account_id.present?
            begin
              if StripeService.check_onboarding_status(b)
                status_tag "Connected", class: "ok"
              else
                status_tag "Setup Incomplete", class: "warning"
              end
            rescue => e
              status_tag "Error", class: "error"
            end
          else
            status_tag "Not Connected", class: "error"
          end
        end
        row "Stripe Connect Account ID" do |b|
          b.stripe_account_id.present? ? b.stripe_account_id : "Not set"
        end
        row "Stripe Customer ID (for subscriptions)" do |b|
          b.stripe_customer_id.present? ? b.stripe_customer_id : "Not set"
        end
        row "Connected At" do |b|
          # This would need to be tracked separately if needed
          "Not tracked"
        end
      end
    end
    
    # Domain Coverage Panel for Premium businesses
    if business.eligible_for_domain_coverage?
      panel "Domain Coverage Information" do
        attributes_table_for business do
          row "Coverage Status" do |b|
            if b.domain_coverage_applied?
              if b.domain_coverage_expired?
                status_tag "Coverage Expired", class: "error"
              elsif b.domain_coverage_expires_soon?
                status_tag "Expiring Soon (#{b.domain_coverage_remaining_days} days)", class: "warning"
              else
                status_tag "Coverage Applied", class: "ok"
              end
            else
              status_tag "Coverage Available", class: "warning"
            end
          end
          row "Coverage Limit" do |b|
            "$#{b.domain_coverage_limit}/year"
          end
          row "Amount Covered" do |b|
            b.domain_cost_covered.present? ? "$#{b.domain_cost_covered}" : "Not applied"
          end
          row "Domain Registrar" do |b|
            b.domain_registrar.present? ? b.domain_registrar.titleize : "Not specified"
          end
          row "Registration Date" do |b|
            b.domain_registration_date&.strftime("%B %d, %Y") || "Not set"
          end
          row "Domain Renewal Date" do |b|
            b.domain_renewal_date&.strftime("%B %d, %Y") || "Not set"
          end
          row "Coverage Expires" do |b|
            if b.domain_coverage_expires_at.present?
              expires_text = b.domain_coverage_expires_at.strftime("%B %d, %Y")
              if b.domain_coverage_expired?
                "#{expires_text} (EXPIRED)"
              elsif b.domain_coverage_expires_soon?
                "#{expires_text} (expires in #{b.domain_coverage_remaining_days} days)"
              else
                expires_text
              end
            else
              "Not set"
            end
          end
          row "Auto-Renewal Status" do |b|
            if b.domain_will_auto_renew?
              status_tag "Auto-Renewal Enabled", class: "ok"
            else
              status_tag "Manual Renewal", class: "warning"
            end
          end
          row "Coverage Notes" do |b|
            b.domain_coverage_notes.present? ? simple_format(b.domain_coverage_notes) : "No notes"
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
