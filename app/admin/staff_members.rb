ActiveAdmin.register StaffMember do

  # See permitted parameters documentation:
  # https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters
  #
  # Uncomment all parameters which should be permitted for assignment
  #
  # permit_params :business_id, :name, :email, :phone, :active, :availability, :settings, :notes
  #
  # or
  #
  # permit_params do
  #   permitted = [:business_id, :name, :email, :phone, :active, :availability, :settings, :notes]
  #   permitted << :other if params[:action] == 'create' && current_user.admin?
  #   permitted
  # end
  
  # Permit parameters for StaffMember
  permit_params :business_id, :user_id, :name, :email, :phone, :active, :notes,
               :position, :photo_url,
               # Simplify back to allowing any hash structure
               availability: {}

  # Custom action for availability management
  member_action :manage_availability, method: [:get, :post] do
    @staff_member = StaffMember.find(params[:id])
    
    if request.post?
      availability_param = params.dig(:staff_member, :availability)
      parsed_availability = nil

      if availability_param.is_a?(String) && availability_param.present?
        begin
          parsed_availability = JSON.parse(availability_param)
        rescue JSON::ParserError => e
          Rails.logger.error("Failed to parse availability JSON: #{e.message}")
          redirect_back fallback_location: admin_staff_member_path(@staff_member), 
                        flash: { error: "Invalid availability format submitted." } and return
        end
      elsif availability_param.is_a?(Hash)
        parsed_availability = availability_param
      else
        parsed_availability = {} 
      end

      # Attempt update if we have a hash
      if parsed_availability.is_a?(Hash) 
        # Removed the explicit .to_json call here - let Rails handle hash assignment
        if @staff_member.update(availability: parsed_availability)
          redirect_to admin_staff_member_path(@staff_member), notice: "Availability updated successfully"
        else
          redirect_back fallback_location: admin_staff_member_path(@staff_member),
                        flash: { error: "Failed to update availability: #{@staff_member.errors.full_messages.join(', ')}" }
        end
      else
        # This case handles if parsing failed and resulted in non-hash (e.g., nil)
        # or if the initial param was neither string nor hash.
        redirect_back fallback_location: admin_staff_member_path(@staff_member),
                      flash: { error: "Invalid or unprocessable availability data format." } # More specific error
      end

    else
      # GET request: Redirect to the show page
      redirect_to admin_staff_member_path(@staff_member), notice: "Manage availability via the show page."
    end
  end
  
  # Add link to the custom action in the action items
  action_item :manage_availability, only: :show do
    link_to 'Manage Availability', manage_availability_admin_staff_member_path(resource)
  end
  
  # Define how the index page displays staff members
  index do
    selectable_column
    id_column
    column :position
    column :user
    column :business do |staff_member|
      if staff_member.business&.id
        link_to staff_member.business.name, admin_business_path(staff_member.business.id)
      elsif staff_member.business
        staff_member.business.name || status_tag("Invalid Business")
      else
        status_tag("None")
      end
    end
    column :name
    column :email
    column :phone
    column "Availability Summary" do |staff|
      if staff.availability.is_a?(Hash)
        days = staff.availability.keys.reject {|k| k.to_s == 'exceptions'}.count
        exceptions = staff.availability.dig('exceptions')&.keys&.count || 0
        day_str = "#{days} #{days == 1 ? 'day' : 'days'}"
        ex_str = "#{exceptions} #{exceptions == 1 ? 'exception' : 'exceptions'}"
        "#{day_str}, #{ex_str}"
      else
        "Not set"
      end
    end
    actions
  end
  
  # Customize the show page
  show do
    attributes_table do
      row :id
      row :business do |staff_member|
        if staff_member.business&.id
          link_to staff_member.business.name, admin_business_path(staff_member.business.id)
        elsif staff_member.business
          staff_member.business.name || status_tag("Invalid Business")
        else
          status_tag("None")
        end
      end
      row :user
      row :name
      row :email
      row :phone
      row :position
      row :photo_url do |staff|
        image_tag(staff.photo_url, width: 100) if staff.photo_url.present?
      end
      row :active
      row :bio
      row :created_at
      row :updated_at
      row "Availability" do |staff|
        link_to "View & Manage Availability", manage_availability_admin_staff_member_path(staff)
        pre JSON.pretty_generate(staff.availability) if staff.availability.is_a?(Hash)
      end
    end
    active_admin_comments
  end
  
  # Customize the form for creating/editing staff members
  form do |f|
    f.inputs "Staff Member Details" do
      f.input :business
      f.input :user
      f.input :name
      f.input :email
      f.input :phone
      f.input :position
      f.input :photo_url
      f.input :active
      f.input :bio, as: :text
    end
    
    f.para "Availability is managed separately using the 'Manage Availability' button on the show page after saving."
    
    f.actions
  end
end
