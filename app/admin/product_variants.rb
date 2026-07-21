ActiveAdmin.register ProductVariant do

  # See permitted parameters documentation:
  # https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters
  #
  # Uncomment all parameters which should be permitted for assignment
  #
  permit_params :name, :price_modifier, :product_id

  # Enable batch actions
  batch_action :destroy, confirm: "Are you sure you want to delete these product variants?" do |ids|
    deleted_count = 0
    failed_count = 0
    
    ProductVariant.where(id: ids).find_each do |variant|
      begin
        variant.destroy!
        deleted_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to delete product variant #{variant.id}: #{e.message}"
      end
    end
    
    if failed_count > 0
      redirect_to collection_path, alert: "#{deleted_count} product variants deleted successfully. #{failed_count} product variants failed to delete."
    else
      redirect_to collection_path, notice: "#{deleted_count} product variants deleted successfully."
    end
  end

  filter :name
  filter :price_modifier
  filter :product

  index do
    selectable_column
    id_column
    column :name
    column :price_modifier do |variant|
      if variant.price_modifier
        number_to_currency(variant.price_modifier)
      else
        "No modifier"
      end
    end
    column :final_price do |variant|
      number_to_currency(variant.final_price)
    end
    column :product
    actions
  end

  form do |f|
    f.inputs do
      f.input :name
      f.input :price_modifier, label: 'Price Modifier (+/-)', hint: 'Amount to add or subtract from base product price'
      f.input :product, collection: Product.order(:name)
    end
    f.actions
  end
end 