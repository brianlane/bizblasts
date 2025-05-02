ActiveAdmin.register TaxRate do

  # See permitted parameters documentation:
  # https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters
  #
  # Uncomment all parameters which should be permitted for assignment
  #
  permit_params :name, :rate, :region, :applies_to_shipping, :business_id
  #
  # or
  #
  # permit_params do
  #   permitted = [:name, :rate, :region, :applies_to_shipping, :business_id]
  #   permitted << :other if params[:action] == 'create' && current_user.admin?
  #   permitted
  # end

  # Optional: Filter by business if super admin needs to see all
  # filter :business, if: proc { current_admin_user.super_admin? }
  filter :name
  filter :rate
  filter :region
  filter :applies_to_shipping
  # Optionally scope filters to current tenant if default scopes don't apply

  index do
    selectable_column
    id_column
    column :name
    column :rate do |tax_rate|
      number_to_percentage(tax_rate.rate * 100, precision: 2)
    end
    column :region
    column :applies_to_shipping
    column :business
    actions
  end

  form do |f|
    f.inputs do
      # Ensure business_id is set correctly, possibly hidden and defaulted
      # f.input :business_id, as: :hidden, input_html: { value: current_business.id } if current_business
      f.input :name
      f.input :rate, hint: 'Enter as a decimal (e.g., 0.08 for 8%)'
      f.input :region
      f.input :applies_to_shipping
    end
    f.actions
  end
end 