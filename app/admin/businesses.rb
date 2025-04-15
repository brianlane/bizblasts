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

  # Permit parameters updated for hostname/host_type
  permit_params :name, :industry, :phone, :email, :website,
                :address, :city, :state, :zip, :description, :time_zone,
                :active, :tier, :service_template_id, 
                :hostname, :host_type # Added new fields

  # Filter options updated
  filter :name
  filter :hostname
  filter :host_type, as: :select, collection: Business.host_types.keys
  filter :tier, as: :select, collection: Business.tiers.keys
  filter :active

  # Index page configuration updated
  index do
    selectable_column
    column :id
    column :name
    column :hostname
    column :host_type
    column :tier
    column :industry
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
      row :industry
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
      f.input :host_type, as: :select, collection: Business.host_types.keys, include_blank: false
      f.input :tier, as: :select, collection: Business.tiers.keys, include_blank: false
      f.input :industry, as: :select, collection: Business.industries.keys, include_blank: false
      f.input :phone
      f.input :email
      f.input :website
      f.input :address
      f.input :city
      f.input :state
      f.input :zip
      f.input :description, as: :text
      f.input :time_zone, as: :select, collection: ActiveSupport::TimeZone.all.map(&:name)
      f.input :active
      f.input :service_template # Assuming this is the correct association name
    end
    f.actions
  end
end
