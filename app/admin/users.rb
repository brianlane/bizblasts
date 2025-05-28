ActiveAdmin.register User do
  permit_params :email, :first_name, :last_name, :role, :business_id, :active, :password, :password_confirmation, :staff_member_id, :phone

  # Filters
  filter :email
  filter :first_name
  filter :last_name
  filter :role, as: :select, collection: User.roles.keys.map { |r| [r.humanize, r] }
  filter :business, as: :select, collection: -> { Business.order(:name).pluck(:name, :id) }
  filter :active
  filter :created_at

  # Enable batch actions
  batch_action :destroy, confirm: "Are you sure you want to delete these users?" do |ids|
    deleted_count = 0
    failed_count = 0
    
    User.where(id: ids).find_each do |user|
      begin
        user.destroy!
        deleted_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to delete user #{user.id}: #{e.message}"
      end
    end
    
    if failed_count > 0
      redirect_to collection_path, alert: "#{deleted_count} users deleted successfully. #{failed_count} users failed to delete."
    else
      redirect_to collection_path, notice: "#{deleted_count} users deleted successfully."
    end
  end

  batch_action :activate, confirm: "Are you sure you want to activate these users?" do |ids|
    updated_count = 0
    failed_count = 0
    
    User.where(id: ids).find_each do |user|
      begin
        # Assuming users have an active field or similar
        user.update!(confirmed_at: Time.current) if user.confirmed_at.nil?
        updated_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to activate user #{user.id}: #{e.message}"
      end
    end
    
    if failed_count > 0
      redirect_to collection_path, alert: "#{updated_count} users activated successfully. #{failed_count} users failed to activate."
    else
      redirect_to collection_path, notice: "#{updated_count} users activated successfully."
    end
  end

  batch_action :deactivate, confirm: "Are you sure you want to deactivate these users?" do |ids|
    updated_count = 0
    failed_count = 0
    
    User.where(id: ids).find_each do |user|
      begin
        # Deactivate by removing confirmation
        user.update!(confirmed_at: nil)
        updated_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to deactivate user #{user.id}: #{e.message}"
      end
    end
    
    if failed_count > 0
      redirect_to collection_path, alert: "#{updated_count} users deactivated successfully. #{failed_count} users failed to deactivate."
    else
      redirect_to collection_path, notice: "#{updated_count} users deactivated successfully."
    end
  end

  # Index Page Configuration
  index do
    selectable_column
    id_column
    column :email
    column "Name", :full_name
    column :role do |user|
      user.role&.humanize
    end
    column :business do |user|
      if user.business&.id
        link_to user.business.name, admin_business_path(user.business.id)
      elsif user.business
        user.business.name || status_tag("Invalid Business")
      else
        status_tag("None")
      end
    end
    column "Staff Member" do |user|
      if user.business && user.staff_member
        link_to(user.staff_member.name, admin_staff_member_path(user.staff_member))
      else
        status_tag("N/A")
      end
    end
    column "Position" do |user|
      user.staff_member&.position
    end
    column "Businesses Count" do |user|
      user.businesses.count
    end
    column :active
    column :confirmed_at
    column :created_at
    actions
  end

  # Show Page Configuration
  show do
    attributes_table do
      row :id
      row :email
      row :full_name
      row :role do |user|
        user.role&.humanize
      end
      row :business if resource.requires_business?
      
      if resource.client?
        row :associated_businesses do |user|
          user.businesses.map do |b|
            if b&.id
              link_to(b.name, admin_business_path(b.id))
            else
              b&.name || "Invalid Business Record"
            end
          end.join(", ").html_safe
        end
      end
      
      row :staff_member do |user|
        if user.business && user.staff_member
          link_to(user.staff_member.name, admin_staff_member_path(user.staff_member))
        else
          "None"
        end
      end
      row :active
      row :confirmed_at
      row :created_at
      row :updated_at
      row :reset_password_sent_at
      row :remember_created_at
    end
    active_admin_comments
  end

  # Form Configuration
  form do |f|
    f.semantic_errors
    f.inputs "User Details" do
      f.input :role, as: :select, collection: User.roles.keys.map { |r| [r.humanize, r] }, input_html: { id: 'user_role_selector' }
      
      f.input :business, as: :select, collection: Business.order(:name).all, 
              wrapper_html: { class: ('input-hidden' unless f.object.requires_business?), id: 'user_business_input' }
              
      f.input :email
      f.input :first_name
      f.input :last_name
      f.input :phone
      
      f.input :staff_member, as: :select, 
              collection: StaffMember.where(business_id: f.object.business_id).order(:name).all,
              wrapper_html: { class: ('input-hidden' unless f.object.requires_business?), id: 'user_staff_member_input' }
              
      f.input :active
      
      if f.object.new_record?
        f.input :password
        f.input :password_confirmation
      end
    end
    f.actions
    
    script do
      raw <<-JS
        document.addEventListener('DOMContentLoaded', function() {
          var roleSelector = document.getElementById('user_role_selector');
          var businessInput = document.getElementById('user_business_input');
          var staffInput = document.getElementById('user_staff_member_input');
          
          function toggleBusinessFields() {
            var selectedRole = roleSelector.value;
            var requiresBusiness = (selectedRole === 'manager' || selectedRole === 'staff');
            
            if (businessInput) {
              businessInput.classList.toggle('input-hidden', !requiresBusiness);
            }
            if (staffInput) {
              staffInput.classList.toggle('input-hidden', !requiresBusiness);
            }
          }
          
          if (roleSelector) {
            roleSelector.addEventListener('change', toggleBusinessFields);
            toggleBusinessFields();
          }
        });
      JS
    end
  end
end
