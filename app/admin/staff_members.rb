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
    link_to "Manage Availability", admin_staff_member_availability_path(staff_member), class: "action_item"
  end

  member_action :availability, method: :get do
    # Render the availability form
    render 'admin/staff_members/availability'
  end

  member_action :update_availability, method: :patch do
    # Initialize availability data structure
    availability_data = {
      'monday' => [],
      'tuesday' => [],
      'wednesday' => [],
      'thursday' => [],
      'friday' => [],
      'saturday' => [],
      'sunday' => [],
      'exceptions' => {}
    }
    
    # Permit the expected nested structure from the form
    availability_params = params.require(:staff_member).require(:availability).permit(
      monday: permit_dynamic_slots,
      tuesday: permit_dynamic_slots,
      wednesday: permit_dynamic_slots,
      thursday: permit_dynamic_slots,
      friday: permit_dynamic_slots,
      saturday: permit_dynamic_slots,
      sunday: permit_dynamic_slots,
      exceptions: {}
    ).to_h
    
    # Extract availability parameters
    days_of_week = %w[monday tuesday wednesday thursday friday saturday sunday]
    
    days_of_week.each do |day|
      # Check for full-day checkbox first
      full_day_param = params.dig(:full_day, day)
      if full_day_param == '1' || full_day_param == 'on'
        # Full 24-hour availability
        availability_data[day] = [{
          'start' => '00:00',
          'end' => '23:59'
        }]
        next
      end
      
      # Get all parameters for this day
      day_params = availability_params[day]
      
      next unless day_params.is_a?(Hash) && day_params.any?
      
      # Process each slot for this day
      slots = []
      day_params.each do |slot_index, slot_data|
        next unless slot_data.is_a?(Hash)
        
        # Extract start and end times - using string keys since we're working with a hash now
        start_time = slot_data["start"]
        end_time = slot_data["end"]
        
        # Only add the slot if both times are present
        if start_time.present? && end_time.present?
          slots << {
            'start' => start_time,
            'end' => end_time
          }
        end
      end
      
      # Add the slots to the availability data
      availability_data[day] = slots
    end

    # Update the staff member with the availability data
    if resource.update(availability: availability_data)
      redirect_to admin_staff_member_path(resource), notice: 'Availability was successfully updated.'
    else
      flash.now[:alert] = resource.errors.full_messages.join(', ')
      render 'admin/staff_members/availability'
    end
  end

  controller do
    private

    # Helper to permit dynamic keys (slot indices) mapping to start/end times
    def permit_dynamic_slots
      # Allows any key (e.g., "0", "1") to contain a hash with "start" and "end"
      Hash.new { |h, k| h[k] = [:start, :end] }
    end
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
