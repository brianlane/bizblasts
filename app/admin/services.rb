ActiveAdmin.register Service do

  # See permitted parameters documentation:
  # https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters
  #
  # Uncomment all parameters which should be permitted for assignment
  #
  # permit_params :business, :name, :description, :price, :duration_minutes, :active, :settings, :notes
  #
  # or
  #
  # permit_params do
  #   permitted = [:business_id, :name, :description, :price, :duration_minutes, :active, :settings, :notes]
  #   permitted << :other if params[:action] == 'create' && current_user.admin?
  #   permitted
  # end
  
  # Define index block to correctly display business link
  index do
    selectable_column
    id_column
    column :name
    column :business do |service|
      if service.business&.id
        link_to service.business.name, admin_business_path(service.business.id)
      elsif service.business
        service.business.name || status_tag("Invalid Business")
      else
        status_tag("None")
      end
    end
    column :description
    column :price do |service|
      number_to_currency(service.price) if service.price
    end
    column :duration_minutes
    column :active
    actions
  end

  # Add permit_params if needed, for example:
  # permit_params :business_id, :name, :description, :price, :duration_minutes, :active, :settings, :notes

end
