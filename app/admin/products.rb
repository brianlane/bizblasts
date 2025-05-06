ActiveAdmin.register Product do

  # See permitted parameters documentation:
  # https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters
  #
  # Uncomment all parameters which should be permitted for assignment
  #
  permit_params :name, :description, :price, :active, :featured, :category_id, :product_type, add_on_service_ids: [], product_variants_attributes: [:id, :name, :sku, :price_modifier, :stock_quantity, :options, :_destroy], images_attributes: [:id, :primary, :position, :_destroy]
  #
  # or
  #
  # permit_params do
  #   permitted = [:name, :description, :price, :active, :featured, :category_id, :business_id]
  #   permitted << :other if params[:action] == 'create' && current_user.admin?
  #   permitted
  # end

  filter :name
  filter :category, collection: -> {
    Category.order(:name)
  }
  filter :active
  filter :featured
  filter :price
  filter :product_type, as: :select, collection: Product.product_types.keys
  filter :created_at

  index do
    selectable_column
    id_column
    column :name
    column :category
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
      row :category
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
              image_tag url_for(product.primary_image.representation(resize_to_limit: [200, 200]))
            end
          end
          product.images.order(:position).each do |img|
            next if img == product.primary_image
            li do 
              image_tag url_for(img.representation(resize_to_limit: [100, 100]))
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
      f.input :category, collection: Category.order(:name)
      f.input :business, as: :select, collection: Business.all.order(:name)
      f.input :name
      f.input :description
      f.input :price
      f.input :product_type, as: :select, collection: Product.product_types.keys
      f.input :active
      f.input :featured
      f.input :images, as: :file, input_html: { multiple: true }
      f.input :add_on_services, as: :check_boxes, collection: Service.all
    end

    f.inputs 'Variants' do
      f.has_many :product_variants, heading: 'Product Variants', allow_destroy: true, new_record: 'Add Variant' do |vf|
        vf.input :name
        vf.input :sku
        vf.input :price_modifier, label: 'Price Modifier (+/-)'
        vf.input :stock_quantity
        vf.input :options
      end
    end

    f.actions
  end

  controller do
    # Override update to handle image attribute errors without rendering the form
    def update
      product = resource
      # Extract and remove images_attributes from params
      attrs = permitted_params[:product].dup
      image_params = attrs.delete(:images_attributes) || attrs.delete('images_attributes')
      # Assign remaining attributes
      product.assign_attributes(attrs)
      # Apply nested image changes if provided
      product.images_attributes = image_params if image_params.present?
      # Attempt save; capture any errors from images_attributes setter or validations
      if product.errors.any? || !product.save
        render plain: product.errors.full_messages.join(', '), status: :unprocessable_entity
      else
        redirect_to resource_path, notice: "Product was successfully updated."
      end
    end
  end
end
