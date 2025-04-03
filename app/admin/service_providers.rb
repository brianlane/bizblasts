ActiveAdmin.register ServiceProvider do

  # See permitted parameters documentation:
  # https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters
  #
  # Uncomment all parameters which should be permitted for assignment
  #
  # permit_params :company_id, :name, :email, :phone, :active, :availability, :settings, :notes
  #
  # or
  #
  # permit_params do
  #   permitted = [:company_id, :name, :email, :phone, :active, :availability, :settings, :notes]
  #   permitted << :other if params[:action] == 'create' && current_user.admin?
  #   permitted
  # end
  
  # Permit parameters for all CRUD operations
  permit_params :company_id, :name, :email, :phone, :active, :notes,
               :availability, :settings

  # Add a custom action for availability management
  member_action :manage_availability, method: [:get, :post] do
    @service_provider = ServiceProvider.find(params[:id])
    
    if request.post?
      if @service_provider.update(availability_params)
        redirect_to admin_service_provider_path(@service_provider), notice: "Availability updated successfully"
      else
        render :manage_availability
      end
    end
  end
  
  # Add link to the custom action in the action items
  action_item :manage_availability, only: :show do
    link_to 'Manage Availability', manage_availability_admin_service_provider_path(resource)
  end
  
  # Define how the index page displays service providers
  index do
    selectable_column
    id_column
    column :company
    column :name
    column :email
    column :phone
    column :active
    column "Availability" do |provider|
      if provider.availability.present? && provider.availability.is_a?(Hash)
        days = provider.availability.keys.reject {|k| k.to_s == 'exceptions'}.count
        exceptions = provider.availability['exceptions']&.keys&.count || 0
        "#{days} days, #{exceptions} exceptions"
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
      row :company
      row :name
      row :email
      row :phone
      row :active
      row :notes
      row :created_at
      row :updated_at
      row "Availability" do |provider|
        if provider.availability.present?
          link_to "View & Manage Availability", manage_availability_admin_service_provider_path(provider)
        else
          link_to "Set Availability", manage_availability_admin_service_provider_path(provider)
        end
      end
    end
    active_admin_comments
  end
  
  # Customize the form for creating/editing service providers
  form do |f|
    f.inputs "Service Provider Details" do
      f.input :company
      f.input :name
      f.input :email
      f.input :phone
      f.input :active
      f.input :notes
      f.input :settings, as: :hidden, input_html: { value: f.object.settings.to_json }
    end
    
    f.para "To manage availability, please save first and then use the 'Manage Availability' feature."
    
    f.actions
  end
  
  # Controller methods for handling the availability management
  controller do
    def availability_params
      params.require(:service_provider).permit(:availability)
    end
  end
  
  # Add JavaScript to allow toggling time slots
  before_action only: :manage_availability do
    script = javascript_include_tag('https://cdn.jsdelivr.net/npm/flatpickr/dist/flatpickr.min.js')
    style = stylesheet_link_tag('https://cdn.jsdelivr.net/npm/flatpickr/dist/flatpickr.min.css')
    active_admin_application.meta_tags[:head] = [script, style].join("\n").html_safe
  end
end
