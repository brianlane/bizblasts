ActiveAdmin.register StaffMember do

  # See permitted parameters documentation:
  # https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters
  #
  # Uncomment all parameters which should be permitted for assignment
  #
  permit_params :name, :email, :phone, :active, :business_id
  #
  # or
  #
  # permit_params do
  #   permitted = [:name, :email, :phone, :active, :business_id]
  #   permitted << :other if params[:action] == 'create' && current_user.admin?
  #   permitted
  # end

  # Enable batch actions
  batch_action :destroy, confirm: "Are you sure you want to delete these staff members?" do |ids|
    deleted_count = 0
    failed_count = 0
    
    StaffMember.where(id: ids).find_each do |staff|
      begin
        staff.destroy!
        deleted_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to delete staff member #{staff.id}: #{e.message}"
      end
    end
    
    if failed_count > 0
      redirect_to collection_path, alert: "#{deleted_count} staff members deleted successfully. #{failed_count} staff members failed to delete."
    else
      redirect_to collection_path, notice: "#{deleted_count} staff members deleted successfully."
    end
  end

  batch_action :activate, confirm: "Are you sure you want to activate these staff members?" do |ids|
    updated_count = 0
    failed_count = 0
    
    StaffMember.where(id: ids).find_each do |staff|
      begin
        staff.update!(active: true)
        updated_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to activate staff member #{staff.id}: #{e.message}"
      end
    end
    
    if failed_count > 0
      redirect_to collection_path, alert: "#{updated_count} staff members activated successfully. #{failed_count} staff members failed to activate."
    else
      redirect_to collection_path, notice: "#{updated_count} staff members activated successfully."
    end
  end

  batch_action :deactivate, confirm: "Are you sure you want to deactivate these staff members?" do |ids|
    updated_count = 0
    failed_count = 0
    
    StaffMember.where(id: ids).find_each do |staff|
      begin
        staff.update!(active: false)
        updated_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to deactivate staff member #{staff.id}: #{e.message}"
      end
    end
    
    if failed_count > 0
      redirect_to collection_path, alert: "#{updated_count} staff members deactivated successfully. #{failed_count} staff members failed to deactivate."
    else
      redirect_to collection_path, notice: "#{updated_count} staff members deactivated successfully."
    end
  end

  filter :name
  filter :email
  filter :phone
  filter :active
  filter :business

  index do
    selectable_column
    id_column
    column :name
    column :email
    column :phone
    column :active
    column :business
    column "Availability" do |staff|
      availability = staff.availability || {}
      days_with_hours = 0
      exceptions_count = 0
      
      %w[monday tuesday wednesday thursday friday saturday sunday].each do |day|
        day_schedule = availability[day] || []
        days_with_hours += 1 if day_schedule.present? && day_schedule.any?
      end
      
      exceptions = availability['exceptions'] || {}
      exceptions_count = exceptions.keys.count
      
      "#{days_with_hours} days, #{exceptions_count} exceptions"
    end
    actions
  end

  show do
    attributes_table do
      row :name
      row :email
      row :phone
      row :bio
      row :active
      row :business
      row :user
      row :created_at
      row :updated_at
      row :status
      row :position
      row :specialties
      row :timezone
      row :availability do |staff|
        if staff.availability.present?
          content_tag :pre, JSON.pretty_generate(staff.availability)
        else
          content_tag :pre, "{}"
        end
      end
      row :color
      row :photo do |staff|
        if staff.photo.attached?
          image_tag rails_public_blob_url(staff.photo.representation(resize_to_limit: [200, 200])), alt: staff.name, style: "max-width: 200px; max-height: 200px;"
        else
          span "No photo", class: "empty"
        end
      end
    end
    
    panel "Staff Member Details" do
      attributes_table_for staff_member do
        row :name
        row :email
        row :phone
        row :bio
        row :active
        row :business
        row :user
        row :created_at
        row :updated_at
        row :status
        row :position
        row :specialties
        row :timezone
        row :availability do |staff|
          if staff.availability.present?
            JSON.pretty_generate(staff.availability)
          else
            "{}"
          end
        end
        row :color
        row :photo do |staff|
          if staff.photo.attached?
            image_tag rails_public_blob_url(staff.photo.representation(resize_to_limit: [200, 200])), alt: staff.name, style: "max-width: 200px; max-height: 200px;"
          else
            span "No photo", class: "empty"
          end
        end
      end
    end
    
    active_admin_comments
  end

  action_item :manage_availability, only: :show do
    link_to "Manage Availability", "#", class: "action_item"
  end

  form do |f|
    f.inputs "Staff Member Details" do
      f.input :name
      f.input :email
      f.input :phone
      f.input :active
      f.input :business, collection: Business.order(:name)
      
      f.para "Availability is managed separately after creating the staff member."
    end
    f.actions
  end
end
