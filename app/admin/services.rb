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
  
  # Permit relevant parameters including the association
  permit_params :business_id, :name, :description, :duration, :price, :active, :featured, :availability_settings, staff_member_ids: []

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
    column :duration
    column :active
    column :featured
    column "Staff Members" do |service|
      service.staff_members.map(&:name).join(", ")
    end
    actions
  end

  # Form definition
  form do |f|
    f.inputs "Service Details" do
      # Select the business (important for multi-tenant)
      f.input :business
      f.input :name
      f.input :description
      f.input :duration
      f.input :price
      f.input :active
      f.input :featured
      # Add staff member selection using checkboxes
      # Filter staff members to only those belonging to the selected business if possible
      # Note: This basic version lists all staff members. A JS solution might be needed 
      # to dynamically update based on the selected business in the form.
      f.input :staff_members, as: :check_boxes, collection: StaffMember.order(:name)
      # Add availability settings field if needed (JSON editor?)
      # f.input :availability_settings, as: :text, input_html: { rows: 5 } 
    end
    f.actions
  end

  # Show page details
  show do
    attributes_table do
      row :name
      row :business do |service|
        link_to service.business.name, admin_business_path(service.business)
      end
      row :description
      row :duration
      row :price do |service|
        number_to_currency(service.price) if service.price
      end
      row :active
      row :featured
      row :availability_settings
      row "Staff Members" do |service|
        service.staff_members.map(&:name).join(", ")
      end
      row :created_at
      row :updated_at
    end
    active_admin_comments
  end

end
