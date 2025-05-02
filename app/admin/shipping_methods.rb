ActiveAdmin.register ShippingMethod do

  # See permitted parameters documentation:
  # https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters
  #
  # Uncomment all parameters which should be permitted for assignment
  #
  permit_params :name, :cost, :active, :business_id
  #
  # or
  #
  # permit_params do
  #   permitted = [:name, :cost, :active, :business_id]
  #   permitted << :other if params[:action] == 'create' && current_user.admin?
  #   permitted
  # end

  # Optional: Filter by business if super admin needs to see all
  # filter :business, if: proc { current_admin_user.super_admin? }
  filter :name
  filter :cost
  filter :active

  index do
    selectable_column
    id_column
    column :name
    column :cost do |method|
      number_to_currency method.cost
    end
    column :active
    column :business
    actions
  end

  form do |f|
    f.inputs do
      # Ensure business_id is set correctly, possibly hidden and defaulted
      # f.input :business_id, as: :hidden, input_html: { value: current_business.id } if current_business
      f.input :name
      f.input :cost
      f.input :active
    end
    f.actions
  end
end 