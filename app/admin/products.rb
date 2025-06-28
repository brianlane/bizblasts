ActiveAdmin.register Product do

  # See permitted parameters documentation:
  # https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters
  #
  # Uncomment all parameters which should be permitted for assignment
  #
  permit_params :name, :description, :price, :active, :featured, :product_type, :allow_discounts, add_on_service_ids: [], product_variants_attributes: [:id, :name, :sku, :price_modifier, :stock_quantity, :_destroy], images_attributes: [:id, :primary, :position, :_destroy]
  #
  # or
  #
  # permit_params do
  #   permitted = [:name, :description, :price, :active, :featured, :business_id]
  #   permitted << :other if params[:action] == 'create' && current_user.admin?
  #   permitted
  # end

  # Enable batch actions
  batch_action :destroy, confirm: "Are you sure you want to delete these products?" do |ids|
    deleted_count = 0
    failed_count = 0
    
    Product.where(id: ids).find_each do |product|
      begin
        product.destroy!
        deleted_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to delete product #{product.id}: #{e.message}"
      end
    end
    
    if failed_count > 0
      redirect_to collection_path, alert: "#{deleted_count} products deleted successfully. #{failed_count} products failed to delete."
    else
      redirect_to collection_path, notice: "#{deleted_count} products deleted successfully."
    end
  end

  batch_action :activate, confirm: "Are you sure you want to activate these products?" do |ids|
    updated_count = 0
    failed_count = 0
    
    Product.where(id: ids).find_each do |product|
      begin
        product.update!(active: true)
        updated_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to activate product #{product.id}: #{e.message}"
      end
    end
    
    if failed_count > 0
      redirect_to collection_path, alert: "#{updated_count} products activated successfully. #{failed_count} products failed to activate."
    else
      redirect_to collection_path, notice: "#{updated_count} products activated successfully."
    end
  end

  batch_action :deactivate, confirm: "Are you sure you want to deactivate these products?" do |ids|
    updated_count = 0
    failed_count = 0
    
    Product.where(id: ids).find_each do |product|
      begin
        product.update!(active: false)
        updated_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to deactivate product #{product.id}: #{e.message}"
      end
    end
    
    if failed_count > 0
      redirect_to collection_path, alert: "#{updated_count} products deactivated successfully. #{failed_count} products failed to deactivate."
    else
      redirect_to collection_path, notice: "#{updated_count} products deactivated successfully."
    end
  end

  filter :name
  filter :active
  filter :featured
  filter :price
  filter :product_type, as: :select, collection: Product.product_types.keys
  filter :created_at

  index do
    selectable_column
    id_column
    column :name
    column :price
    column :product_type
    column :active
    column :featured
    column :business
    column :created_at
    actions
  end

  show do
    attributes_table do
      row :name
      row :description
      row :price
      row :active
      row :featured
      row :business
      row :created_at
      row :updated_at
    end

    panel "Images" do
      if product.images.attached?
        ul do
          if product.primary_image.present?
            li "Primary Image:"
            li do
              image_tag rails_public_blob_url(product.primary_image.representation(resize_to_limit: [200, 200]))
            end
          end
          product.images.order(:position).each do |img|
            next if img == product.primary_image
            li do 
              image_tag rails_public_blob_url(img.representation(resize_to_limit: [100, 100]))
            end
          end
        end
      end
    end

    panel "Variants" do
      table_for product.product_variants do
        column :name
        column :price_modifier
        column :final_price do |variant|
          number_to_currency variant.final_price
        end
        column :stock_quantity
        column :actions do |variant|
          link_to "Edit", edit_admin_product_variant_path(product, variant)
        end
      end
    end
    active_admin_comments
  end

  form do |f|
    f.inputs 'Product Details' do
      f.input :business, as: :select, collection: Business.all.order(:name)
      f.input :name
      f.input :description
      f.input :price
      f.input :product_type, as: :select, collection: Product.product_types.keys
      f.input :active
      f.input :featured
      f.input :allow_discounts, label: 'Allow Discount Codes', hint: 'When unchecked, this product will be excluded from all discount codes and promo codes'
      f.input :images, as: :file, input_html: { multiple: true }
      
      # Filter add_on_services by the selected business
      f.input :add_on_services, as: :check_boxes, 
        collection: -> {
          business_id = f.object.business_id
          if business_id.present?
            Service.where(business_id: business_id).order(:name)
          else
            Service.all.order(:name)
          end
        }
    end
    
    f.inputs 'Variant Display Settings' do
      f.input :variant_label_text, label: 'Variant Selection Label', hint: 'Text shown above variant dropdown (e.g., "Choose a size:", "Select color:"). Products with only one variant will automatically hide the dropdown.'
    end

    f.inputs 'Variants' do
      f.has_many :product_variants, heading: 'Product Variants', allow_destroy: true, new_record: 'Add Variant' do |vf|
        vf.input :name
        vf.input :sku
        vf.input :price_modifier, label: 'Price Modifier (+/-)'
        vf.input :stock_quantity
      end
    end

    f.actions
  end

  controller do
    # Override update to handle image attribute errors without rendering the form
    def update
      product = resource
      
      # Use Rails' standard update method which will automatically handle:
      # - images_attributes for existing image management (via our custom setter)  
      # - images for new image uploads (via our custom images= method)
      if product.update(permitted_params[:product])
        redirect_to resource_path, notice: "Product was successfully updated."
      else
        render plain: product.errors.full_messages.join(', '), status: :unprocessable_entity
      end
    end
  end
end
