ActiveAdmin.register Category do

  # See permitted parameters documentation:
  # https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters
  #
  # Uncomment all parameters which should be permitted for assignment
  #
  permit_params :name, :business_id
  #
  # or
  #
  # permit_params do
  #   permitted = [:name, :business_id]
  #   permitted << :other if params[:action] == 'create' && current_user.admin?
  #   permitted
  # end

  filter :name
  filter :created_at

  index do
    selectable_column
    id_column
    column :name
    column :business
    column :created_at
    actions
  end

  form do |f|
    f.inputs do
      # Ensure business_id is set correctly, possibly hidden and defaulted
      # f.input :business_id, as: :hidden, input_html: { value: current_business.id } if current_business
      f.input :name
    end
    f.actions
  end
end
