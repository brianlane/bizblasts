ActiveAdmin.register ProductVariant do

  # See permitted parameters documentation:
  # https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters
  #
  # Uncomment all parameters which should be permitted for assignment
  #
  permit_params :name, :price, :active, :product_id
  #
  # or
  #
  # permit_params do
  #   permitted = [:name, :price, :active, :product_id]
  #   permitted << :other if params[:action] == 'create' && current_user.admin?
  #   permitted
  # end

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

  batch_action :activate, confirm: "Are you sure you want to activate these product variants?" do |ids|
    updated_count = 0
    failed_count = 0
    
    ProductVariant.where(id: ids).find_each do |variant|
      begin
        variant.update!(active: true)
        updated_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to activate product variant #{variant.id}: #{e.message}"
      end
    end
    
    if failed_count > 0
      redirect_to collection_path, alert: "#{updated_count} product variants activated successfully. #{failed_count} product variants failed to activate."
    else
      redirect_to collection_path, notice: "#{updated_count} product variants activated successfully."
    end
  end

  batch_action :deactivate, confirm: "Are you sure you want to deactivate these product variants?" do |ids|
    updated_count = 0
    failed_count = 0
    
    ProductVariant.where(id: ids).find_each do |variant|
      begin
        variant.update!(active: false)
        updated_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to deactivate product variant #{variant.id}: #{e.message}"
      end
    end
    
    if failed_count > 0
      redirect_to collection_path, alert: "#{updated_count} product variants deactivated successfully. #{failed_count} product variants failed to deactivate."
    else
      redirect_to collection_path, notice: "#{updated_count} product variants deactivated successfully."
    end
  end

  filter :name
  filter :price
  filter :active
  filter :product

  index do
    selectable_column
    id_column
    column :name
    column :price do |variant|
      number_to_currency(variant.price) if variant.price
    end
    column :active
    column :product
    actions
  end

  form do |f|
    f.inputs do
      f.input :name
      f.input :price
      f.input :active
      f.input :product, collection: Product.order(:name)
    end
    f.actions
  end
end 