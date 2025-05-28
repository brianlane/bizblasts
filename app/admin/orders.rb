ActiveAdmin.register Order do

  # See permitted parameters documentation:
  # https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters
  #
  # Uncomment all parameters which should be permitted for assignment
  #
  permit_params :tenant_customer_id, :status, :shipping_method_id, :tax_rate_id, :business_id,
                :shipping_address, :billing_address, :notes, :order_type,
                line_items_attributes: [:id, :product_variant_id, :quantity, :price, :_destroy]
  # Note: total_amount, shipping_amount, tax_amount are usually calculated, not permitted directly
  # order_number is usually set automatically
  #
  # or
  #
  # permit_params do
  #   permitted = [:tenant_customer_id, :status, :shipping_method_id, :tax_rate_id, :business_id, :shipping_address, :billing_address, :notes, :order_type]
  #   permitted << :other if params[:action] == 'create' && current_user.admin?
  #   permitted
  # end

  # Enable batch actions
  batch_action :destroy, confirm: "Are you sure you want to delete these orders?" do |ids|
    deleted_count = 0
    failed_count = 0
    
    Order.where(id: ids).find_each do |order|
      begin
        order.destroy!
        deleted_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to delete order #{order.id}: #{e.message}"
      end
    end
    
    if failed_count > 0
      redirect_to collection_path, alert: "#{deleted_count} orders deleted successfully. #{failed_count} orders failed to delete."
    else
      redirect_to collection_path, notice: "#{deleted_count} orders deleted successfully."
    end
  end

  # Add batch action to mark orders as business_deleted (useful for orphaned orders)
  batch_action :mark_as_business_deleted, confirm: "Are you sure you want to mark these orders as business deleted?" do |ids|
    updated_count = 0
    failed_count = 0
    
    Order.where(id: ids).find_each do |order|
      begin
        order.mark_business_deleted!
        updated_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to mark order #{order.id} as business deleted: #{e.message}"
      end
    end
    
    if failed_count > 0
      redirect_to collection_path, alert: "#{updated_count} orders marked as business deleted. #{failed_count} orders failed to update."
    else
      redirect_to collection_path, notice: "#{updated_count} orders marked as business deleted."
    end
  end

  filter :tenant_customer, collection: -> {
    TenantCustomer.order(:name)
  }
  filter :order_number
  filter :status, as: :select, collection: Order.statuses.keys
  filter :order_type, as: :select, collection: Order.order_types.keys
  filter :total_amount
  filter :shipping_method, collection: -> {
    ShippingMethod.order(:name)
  }
  filter :tax_rate, collection: -> {
    TaxRate.order(:name)
  }
  filter :created_at

  index do
    selectable_column
    id_column
    column :order_number
    column :tenant_customer
    column :status
    column :order_type
    column :total_amount do |order|
      number_to_currency order.total_amount
    end
    column :shipping_method
    column :tax_rate
    column :business
    column :created_at
    actions
  end

  show do
    attributes_table do
      row :order_number
      row :tenant_customer
      row :business
      row :status
      row :order_type
      row :shipping_method
      row :tax_rate
      row :shipping_amount do |order| number_to_currency order.shipping_amount end
      row :tax_amount do |order| number_to_currency order.tax_amount end
      row :total_amount do |order| number_to_currency order.total_amount end
      row :shipping_address
      row :billing_address
      row :notes
      row :created_at
      row :updated_at
    end

    panel "Line Items" do
      table_for order.line_items do
        column :product_variant
        column :quantity
        column :price do |item| number_to_currency item.price end
        column :total_amount do |item| number_to_currency item.total_amount end
      end
    end
    active_admin_comments
  end

  form do |f|
    f.inputs 'Order Details' do
      # Scope of tenant_customer dropdown
      f.input :tenant_customer, collection: TenantCustomer.order(:name)
      f.input :status, as: :select, collection: Order.statuses.keys, include_blank: false
      f.input :order_type, as: :select, collection: Order.order_types.keys, include_blank: false
      f.input :shipping_method, collection: ShippingMethod.where(active: true).order(:name)
      f.input :tax_rate, collection: TaxRate.order(:name)
      f.input :shipping_address
      f.input :billing_address
      f.input :notes
    end

    f.inputs 'Line Items' do
      f.has_many :line_items, heading: 'Line Items', allow_destroy: true, new_record: 'Add Item' do |lif|
        # Scope product variants to the current business
        product_variants_collection = ProductVariant.joins(:product)
                                        .includes(:product)
                                        .order('products.name ASC, product_variants.name ASC')
                                        .map { |pv| ["#{pv.product.name} - #{pv.name}", pv.id] }
        lif.input :product_variant, as: :select, collection: product_variants_collection, include_blank: 'Select Variant'
        lif.input :quantity
        # Price is usually set automatically based on variant, maybe make readonly
        lif.input :price, input_html: { readonly: true } # Consider removing or making read-only
      end
    end

    # Display calculated totals (read-only)
    f.inputs 'Totals', for: [:totals, f.object] do |total_f|
        total_f.input :shipping_amount, input_html: { readonly: true, disabled: true }
        total_f.input :tax_amount, input_html: { readonly: true, disabled: true }
        total_f.input :total_amount, input_html: { readonly: true, disabled: true }
    end

    f.actions
  end
end 