ActiveAdmin.register Service do

  # See permitted parameters documentation:
  # https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters
  #
  # Uncomment all parameters which should be permitted for assignment
  #
  permit_params :name, :description, :price, :duration, :active, :business_id, :category_id
  #
  # or
  #
  # permit_params do
  #   permitted = [:name, :description, :price, :duration, :active, :business_id, :category_id]
  #   permitted << :other if params[:action] == 'create' && current_user.admin?
  #   permitted
  # end

  # Enable batch actions
  batch_action :destroy, confirm: "Are you sure you want to delete these services?" do |ids|
    deleted_count = 0
    failed_count = 0
    
    Service.where(id: ids).find_each do |service|
      begin
        service.destroy!
        deleted_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to delete service #{service.id}: #{e.message}"
      end
    end
    
    if failed_count > 0
      redirect_to collection_path, alert: "#{deleted_count} services deleted successfully. #{failed_count} services failed to delete."
    else
      redirect_to collection_path, notice: "#{deleted_count} services deleted successfully."
    end
  end

  batch_action :activate, confirm: "Are you sure you want to activate these services?" do |ids|
    updated_count = 0
    failed_count = 0
    
    Service.where(id: ids).find_each do |service|
      begin
        service.update!(active: true)
        updated_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to activate service #{service.id}: #{e.message}"
      end
    end
    
    if failed_count > 0
      redirect_to collection_path, alert: "#{updated_count} services activated successfully. #{failed_count} services failed to activate."
    else
      redirect_to collection_path, notice: "#{updated_count} services activated successfully."
    end
  end

  batch_action :deactivate, confirm: "Are you sure you want to deactivate these services?" do |ids|
    updated_count = 0
    failed_count = 0
    
    Service.where(id: ids).find_each do |service|
      begin
        service.update!(active: false)
        updated_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to deactivate service #{service.id}: #{e.message}"
      end
    end
    
    if failed_count > 0
      redirect_to collection_path, alert: "#{updated_count} services deactivated successfully. #{failed_count} services failed to deactivate."
    else
      redirect_to collection_path, notice: "#{updated_count} services deactivated successfully."
    end
  end

  filter :name
  filter :description
  filter :price
  filter :duration
  filter :active
  filter :business
  filter :category

  index do
    selectable_column
    id_column
    column :name
    column :description
    column :price do |service|
      number_to_currency(service.price) if service.price
    end
    column :duration do |service|
      "#{service.duration} minutes" if service.duration
    end
    column :active
    column :business
    column :category
    actions
  end

  form do |f|
    f.inputs do
      f.input :name
      f.input :description
      f.input :price
      f.input :duration, label: 'Duration (minutes)'
      f.input :active
      f.input :business, collection: Business.order(:name)
      f.input :category, collection: Category.order(:name)
    end
    f.actions
  end

  # Permit relevant parameters including the association and nested image attributes
  permit_params :business_id, :name, :description, :duration, :price, :active, :featured, :availability_settings, staff_member_ids: [], add_on_product_ids: [], type: [], min_bookings: [], max_bookings: [], spots: [], images_attributes: [:id, :primary, :position, :_destroy]

  # Define index block to correctly display business link
  index do
    selectable_column
    id_column
    column :name
    column :business do |service|
      if service.business&.id
        link_to service.business.name, admin_business_path(service.business.id)
      elsif service.business
        service.business.name || status_tag("Invalid Business")
      else
        status_tag("None")
      end
    end
    column :description
    column :price do |service|
      number_to_currency(service.price) if service.price
    end
    column :duration
    column :active
    column :featured
    column "Staff Members" do |service|
      service.staff_members.map(&:name).join(", ")
    end
    actions
  end

  filter :name
  filter :price
  filter :duration
  filter :active
  filter :featured

  # Form definition
  form do |f|
    f.inputs "Service Details" do
      # Select the business (important for multi-tenant)
      f.input :business
      f.input :name
      f.input :description
      f.input :duration
      f.input :price
      f.input :active
      f.input :featured
      
      f.input :type, as: :select, collection: Service.types.keys.map { |k| [k.humanize, k] }, include_blank: false, input_html: { id: 'service_type_select' }

      f.input :min_bookings
      f.input :max_bookings

      # Add staff member selection using checkboxes
      # Filter staff members to only those belonging to the selected business if possible
      # Note: This basic version lists all staff members. A JS solution might be needed 
      # to dynamically update based on the selected business in the form.
      f.input :staff_members, as: :check_boxes, collection: StaffMember.order(:name)
      # Add availability settings field if needed (JSON editor?)
      # f.input :availability_settings, as: :text, input_html: { rows: 5 } 
      
      # Only show service and mixed products from the selected business
      f.input :add_on_products, as: :check_boxes, 
        collection: -> {
          business_id = f.object.business_id
          if business_id.present?
            Product.where(business_id: business_id, product_type: [:service, :mixed]).order(:name)
          else
            Product.where(product_type: [:service, :mixed]).order(:name)
          end
        }

      # Image upload field
      f.input :images, as: :file, input_html: { multiple: true }

    end
    f.actions
  end

  # Show page details
  show do
    attributes_table do
      row :name
      row :business do |service|
        link_to service.business.name, admin_business_path(service.business)
      end
      row :description
      row :duration
      row :price do |service|
        number_to_currency(service.price) if service.price
      end
      row :active
      row :featured
      row :type do |service|
        service.type.humanize if service.type
      end
      row :min_bookings if resource.experience?
      row :max_bookings if resource.experience?
      row :spots if resource.experience?
      row :availability_settings
      row "Staff Members" do |service|
        service.staff_members.map(&:name).join(", ")
      end
      row :created_at
      row :updated_at
    end

    # Images Panel
    panel "Images" do
      if service.images.attached?
        ul do
          # Display primary image if exists
          if service.primary_image.present?
            li "Primary Image:"
            li do
              image_tag url_for(service.primary_image.representation(resize_to_limit: [200, 200]))
            end
          end
          # Display other images in order
          service.images.ordered.each do |img|
             next if service.primary_image.present? && img.id == service.primary_image.id
            li do 
              image_tag url_for(img.representation(resize_to_limit: [100, 100]))
            end
          end
        end
      else
        p "No images attached."
      end
    end

    active_admin_comments
  end

  controller do
    # Override update action to handle nested image attributes
    def update
      service = resource
      # Extract and remove images_attributes from params if present
      attrs = permitted_params[:service].dup
      image_params = attrs.delete(:images_attributes) || attrs.delete('images_attributes')

      # Assign remaining attributes
      service.assign_attributes(attrs)

      # Apply nested image changes if provided
      if image_params.present?
         # Process existing and new images
         image_params.each do |i, image_data|
           if image_data[:id].present?
             # Existing image: handle destroy, primary, position
             attachment = service.images.attachments.find_by(id: image_data[:id])
             if attachment
               if image_data[:_destroy].present? && ActiveModel::Type::Boolean.new.cast(image_data[:_destroy])
                 attachment.purge # Delete the attachment
               else
                 # Update primary and position (position is expected in image_params for reordering)
                 update_attrs = {}
                 update_attrs[:primary] = ActiveModel::Type::Boolean.new.cast(image_data[:primary]) if image_data.key?(:primary)
                 update_attrs[:position] = image_data[:position] if image_data.key?(:position)
                 attachment.update(update_attrs) if update_attrs.any?
               end
             end
           elsif image_data[:io].present? # Check for new file upload (io or tempfile)
              # New image upload - handled by `has_many_attached` and form `multiple: true`
              # Active Admin handles appending new files automatically when passed in the main `:images` param
              # We don't need explicit logic here for NEW files, only for managing existing ones.
              # However, Active Admin form passes *all* files (existing and new) under `:images` param
              # We need to permit `:images` as an array in permit_params for new uploads.
              # The `images_attributes` setter is primarily for managing existing attachments (destroy, primary, position).

              # Re-add the new image data to the main images param for ActiveStorage to process
              # This seems counter-intuitive, but ActiveStorage's `attach` expects this structure
              attrs[:images] ||= []
              attrs[:images] << image_data
           end
         end

         # Need to re-assign the filtered attrs to the service for ActiveStorage to attach new files
         service.assign_attributes(attrs)

         # After processing existing images (destroy, primary, position), handle reordering of remaining images
         # This requires collecting the ordered IDs from image_params (if provided) and calling a reorder method
         # Assuming image_params contains position for all *remaining* images for reordering
         ordered_image_ids = image_params.values
                                       .reject { |data| ActiveModel::Type::Boolean.new.cast(data[:_destroy]) || data[:id].blank? }
                                       .sort_by { |data| data[:position].to_i }
                                       .map { |data| data[:id].to_i }

         if ordered_image_ids.present? && ordered_image_ids.size == service.images.attachments.count
            # Ensure we only try to reorder if the number of ordered IDs matches current attachments
            # This prevents errors if some attachments were just destroyed
            service.images.attachments.each do |attachment|
               new_position = ordered_image_ids.index(attachment.id)
               attachment.update(position: new_position) if new_position.present?
            end
         end

      end # if image_params.present?

      # Attempt save; capture any errors from images_attributes setter or validations
      if service.errors.any? || !service.save
        # If saving fails, manually re-render the form with errors
        # Need to reload associations for the form to render correctly
        # service.reload # Might be needed depending on how errors affect associations
        flash.now[:error] = service.errors.full_messages.join(', ')
        render :edit, status: :unprocessable_entity
      else
        redirect_to resource_path(service), notice: "Service was successfully updated."
      end
    end

    # Override create action as well to handle potential image errors
    def create
      service = Service.new(permitted_params[:service])
      service.business = current_business # Assuming current_business helper is available

      if service.save
        redirect_to resource_path(service), notice: "Service was successfully created."
      else
        flash.now[:error] = service.errors.full_messages.join(', ')
        render :new, status: :unprocessable_entity
      end
    end

  end # controller do

end
