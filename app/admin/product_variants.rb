ActiveAdmin.register ProductVariant do

  # See permitted parameters documentation:
  # https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters
  #
  # Uncomment all parameters which should be permitted for assignment
  #
  permit_params :product_id, :name, :price_modifier, :stock_quantity
  #
  # or
  #
  # permit_params do
  #   permitted = [:product_id, :name, :price_modifier, :stock_quantity]
  #   permitted << :other if params[:action] == 'create' && current_user.admin?
  #   permitted
  # end

  # Filters
  filter :product, collection: -> {
    # Filter products by current business
    Product.order(:name)
  }
  filter :name
  filter :stock_quantity
  filter :price_modifier


  index do
    selectable_column
    id_column
    column :product
    column :name
    column :price_modifier
    column :final_price do |variant|
      number_to_currency variant.final_price
    end
    column :stock_quantity
    actions
  end

  form do |f|
    f.inputs do
      # Ensure Product selection is scoped to the current business
      f.input :product, collection: Product.order(:name)
      f.input :name
      f.input :price_modifier, label: 'Price Modifier (+/-)'
      f.input :stock_quantity
    end
    f.actions
  end
end 