ActiveAdmin.register LineItem do

  # See permitted parameters documentation:
  # https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters
  #
  # Uncomment all parameters which should be permitted for assignment
  #
  permit_params :lineable_type, :lineable_id, :product_variant_id, :quantity, :price, :total_amount
  # Note: price and total_amount are often calculated, consider removing from direct edit
  #
  # or
  #
  # permit_params do
  #   permitted = [:lineable_type, :lineable_id, :product_variant_id, :quantity, :price, :total_amount]
  #   permitted << :other if params[:action] == 'create' && current_user.admin?
  #   permitted
  # end

  # HIDE LineItem from main menu unless needed for direct management
  menu false

  # Filters (adjust based on whether Orders or Invoices are primary use)
  filter :product_variant_product_name_cont, label: 'Product Name'
  filter :product_variant_name_cont, label: 'Variant Name'
  filter :quantity
  filter :price
  filter :total_amount
  filter :lineable_type, as: :select, collection: ['Order', 'Invoice'] # Adjust as needed
  filter :created_at

  index do
    selectable_column
    id_column
    column :lineable
    column :product_variant do |item|
      if item.product_variant
        link_to "#{item.product_variant.product.name} - #{item.product_variant.name}", admin_product_variant_path(item.product_variant)
      end
    end
    column :quantity
    column :price do |item| number_to_currency item.price end
    column :total_amount do |item| number_to_currency item.total_amount end
    actions
  end

  # Form - Usually managed via nested form in Order/Invoice
  form do |f|
    f.inputs do
      # These are hard to manage directly, better via nested forms
      f.input :lineable_type, as: :select, collection: ['Order', 'Invoice']
      f.input :lineable_id # Needs dynamic update based on type
      f.input :product_variant # Needs scoping based on business
      f.input :quantity
      f.input :price # Readonly? Calculated?
      f.input :total_amount # Readonly? Calculated?
    end
    f.actions
  end
end 