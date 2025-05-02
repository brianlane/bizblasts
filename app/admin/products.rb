ActiveAdmin.register Product do

  # See permitted parameters documentation:
  # https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters
  #
  # Uncomment all parameters which should be permitted for assignment
  #
  permit_params :name, :description, :price, :active, :featured, :category_id, :business_id,
                images: [], product_variants_attributes: [:id, :name, :price_modifier, :stock_quantity, :_destroy]
  #
  # or
  #
  # permit_params do
  #   permitted = [:name, :description, :price, :active, :featured, :category_id, :business_id]
  #   permitted << :other if params[:action] == 'create' && current_user.admin?
  #   permitted
  # end

  # Optional: Filter by business if super admin needs to see all
  # filter :business, if: proc { current_admin_user.super_admin? }
  filter :name
  filter :category, collection: -> {
    Category.order(:name)
  }
  filter :active
  filter :featured
  filter :price
  filter :created_at

  index do
    selectable_column
    id_column
    column :name
    column :category
    column :price
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
      row :images do |product|
        if product.images.attached?
          ul do
            product.images.each do |img|
              li do
                image_tag url_for(img.representation(resize_to_limit: [100, 100]))
              end
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
          # Link to edit variant - might need custom route or link to variant admin
          # link_to "Edit", edit_admin_product_variant_path(variant) 
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
      f.input :active
      f.input :featured
      f.input :images, as: :file, input_html: { multiple: true }
    end

    f.inputs 'Variants' do
      f.has_many :product_variants, heading: 'Product Variants', allow_destroy: true, new_record: 'Add Variant' do |vf|
        vf.input :name
        vf.input :price_modifier, label: 'Price Modifier (+/-)'
        vf.input :stock_quantity
      end
    end

    f.actions
  end
end
