module BusinessManager
  class ProductsController < BaseController # Inherit from your base controller for this namespace
    include ImageCroppable

    before_action :set_product, only: [:show, :edit, :update, :destroy, :update_position, :move_up, :move_down, :add_image, :remove_image, :crop_image]

    # GET /manage/products
    def index
      @products = current_business.products.positioned.includes(:product_variants, images_attachments: :blob)
      
      # Apply pagination if using kaminari
      @products = @products.page(params[:page]) if @products.respond_to?(:page)
    end

    # GET /manage/products/:id
    def show
      # @product set by before_action
      # No need to load associations here, handled in set_product
    end

    # GET /manage/products/new
    def new
      @product = current_business.products.new
      # No automatic variant build; variants are opt-in via Add Variant link
    end

    # POST /manage/products
    def create
      @product = current_business.products.new(product_params)
      if @product.save
        # Process any image crops after save
        process_image_crops if params.dig(:product, :images_crop_data).present?
        redirect_to business_manager_product_path(@product), notice: 'Product was successfully created.'
      else
        flash.now[:alert] = @product.errors.full_messages.to_sentence
        render :new, status: :unprocessable_content
      end
    end

    # GET /manage/products/:id/edit
    def edit
      # @product set by before_action
      # No automatic variant build; variants are opt-in via Add Variant link
    end

    # PATCH/PUT /manage/products/:id
    def update
      if @product.update(product_params_without_images) && handle_image_updates
        # Process any image crops after save
        process_image_crops if params.dig(:product, :images_crop_data).present?
        redirect_to business_manager_product_path(@product), notice: 'Product was successfully updated.'
      else
        flash.now[:alert] = @product.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_content
      end
    end

    # DELETE /manage/products/:id
    def destroy
      @product.destroy
      redirect_to business_manager_products_path, notice: 'Product was successfully deleted.'
    end

    def update_position
      new_position = params[:position].to_i
      
      if @product.move_to_position(new_position)
        render json: { status: 'success', message: 'Product position updated successfully' }
      else
        render json: { status: 'error', message: 'Failed to update product position' }, status: :unprocessable_content
      end
    end

    def move_up
      # Check if product is already at the top
      products_list = current_business.products.positioned.to_a
      current_index = products_list.index(@product)
      
      if current_index.nil?
        respond_to do |format|
          format.json { render json: { status: 'error', message: 'Product not found' }, status: :not_found }
          format.html { redirect_to business_manager_products_path, alert: 'Product not found' }
        end
        return
      end
      
      if current_index == 0
        # Already at the top, do nothing but return success
        respond_to do |format|
          format.json { render json: { status: 'success', message: 'Product is already at the top' } }
          format.html { redirect_to business_manager_products_path, notice: 'Product is already at the top' }
        end
        return
      end
      
      # Move to previous position
      target_product = products_list[current_index - 1]
      if @product.move_to_position(target_product.position)
        respond_to do |format|
          format.json { render json: { status: 'success', message: 'Product moved up successfully' } }
          format.html { redirect_to business_manager_products_path, notice: 'Product moved up successfully' }
        end
      else
        respond_to do |format|
          format.json { render json: { status: 'error', message: 'Failed to move product up' }, status: :unprocessable_content }
          format.html { redirect_to business_manager_products_path, alert: 'Failed to move product up' }
        end
      end
    end

    def move_down
      # Check if product is already at the bottom
      products_list = current_business.products.positioned.to_a
      current_index = products_list.index(@product)

      if current_index.nil?
        respond_to do |format|
          format.json { render json: { status: 'error', message: 'Product not found' }, status: :not_found }
          format.html { redirect_to business_manager_products_path, alert: 'Product not found' }
        end
        return
      end

      if current_index == products_list.length - 1
        # Already at the bottom, do nothing but return success
        respond_to do |format|
          format.json { render json: { status: 'success', message: 'Product is already at the bottom' } }
          format.html { redirect_to business_manager_products_path, notice: 'Product is already at the bottom' }
        end
        return
      end

      # Move to next position
      target_product = products_list[current_index + 1]
      if @product.move_to_position(target_product.position)
        respond_to do |format|
          format.json { render json: { status: 'success', message: 'Product moved down successfully' } }
          format.html { redirect_to business_manager_products_path, notice: 'Product moved down successfully' }
        end
      else
        respond_to do |format|
          format.json { render json: { status: 'error', message: 'Failed to move product down' }, status: :unprocessable_content }
          format.html { redirect_to business_manager_products_path, alert: 'Failed to move product down' }
        end
      end
    end

    # POST /business_manager/products/:id/add_image
    # Async image upload endpoint
    def add_image
      image_file = params[:image]

      unless image_file.present?
        render json: { success: false, error: "No image provided" }, status: :unprocessable_entity
        return
      end

      # Validate file type
      allowed_types = %w[image/png image/jpeg image/gif image/webp image/heic image/heif]
      unless allowed_types.include?(image_file.content_type)
        render json: { success: false, error: "Invalid file type. Allowed: PNG, JPEG, GIF, WebP, HEIC, HEIF" }, status: :unprocessable_entity
        return
      end

      # Validate file size (15MB max)
      max_size = 15.megabytes
      if image_file.size > max_size
        render json: { success: false, error: "File too large. Maximum size is 15MB." }, status: :unprocessable_entity
        return
      end

      begin
        @product.images.attach(image_file)
        new_attachment = @product.images.attachments.last

        if new_attachment.persisted?
          render json: {
            success: true,
            attachment_id: new_attachment.id,
            filename: new_attachment.filename.to_s,
            thumbnail_url: rails_public_blob_url(new_attachment.representation(resize_to_limit: [120, 120])),
            full_url: rails_public_blob_url(new_attachment)
          }
        else
          render json: { success: false, error: "Failed to save image" }, status: :unprocessable_entity
        end
      rescue StandardError => e
        Rails.logger.error "[PRODUCTS] Image upload error: #{e.message}"
        render json: { success: false, error: "Upload failed: #{e.message}" }, status: :unprocessable_entity
      end
    end

    # DELETE /business_manager/products/:id/remove_image/:attachment_id
    # Async image removal endpoint
    def remove_image
      attachment = @product.images.attachments.find_by(id: params[:attachment_id])

      unless attachment
        render json: { success: false, error: "Image not found" }, status: :not_found
        return
      end

      begin
        attachment.purge
        render json: { success: true, message: "Image removed successfully" }
      rescue StandardError => e
        Rails.logger.error "[PRODUCTS] Image removal error: #{e.message}"
        render json: { success: false, error: "Failed to remove image: #{e.message}" }, status: :unprocessable_entity
      end
    end

    # POST /business_manager/products/:id/crop_image/:attachment_id
    # Server-side image cropping endpoint
    def crop_image
      attachment = @product.images.attachments.find_by(id: params[:attachment_id])

      unless attachment
        render json: { success: false, error: "Image not found" }, status: :not_found
        return
      end

      # Validate that the attachment is a valid image
      unless valid_image_for_crop?(attachment)
        render json: { success: false, error: "Invalid image type" }, status: :unprocessable_entity
        return
      end

      crop_data = params[:crop_data]
      unless crop_data.present?
        render json: { success: false, error: "No crop data provided" }, status: :unprocessable_entity
        return
      end

      # Parse crop data using the concern's secure method (replaces to_unsafe_h)
      crop_params = parse_crop_params(crop_data)

      if crop_params.blank?
        render json: { success: false, error: "Invalid crop data format" }, status: :unprocessable_entity
        return
      end

      begin
        result = ImageCropService.crop(attachment, crop_params)

        if result
          # Return updated thumbnail URL
          render json: {
            success: true,
            message: "Image cropped successfully",
            thumbnail_url: rails_public_blob_url(attachment.representation(resize_to_limit: [120, 120])),
            full_url: rails_public_blob_url(attachment)
          }
        else
          render json: { success: false, error: "Crop operation failed" }, status: :unprocessable_entity
        end
      rescue StandardError => e
        Rails.logger.error "[PRODUCTS] Image crop error: #{e.message}"
        render json: { success: false, error: "Crop failed: #{e.message}" }, status: :unprocessable_entity
      end
    end

    private

    def set_product
      @product = current_business.products.find(params[:id])
    end

    def product_params
      params.require(:product).permit(
        :name, :description, :price, :active, :featured, :product_type, :tips_enabled, :allow_discounts,
        :stock_quantity, # If product can be sold without variants
        :subscription_enabled, :subscription_discount_percentage, :subscription_billing_cycle, :subscription_out_of_stock_action, :allow_customer_preferences,
        :show_stock_to_customers, # Allow customers to see stock quantities
        :hide_when_out_of_stock, # Hide product when out of stock
        :variant_label_text, # Variant label customization
        :position, # Allow position updates
        :document_template_id, # Allow associating a document template (product agreement/terms)
        add_on_service_ids: [],
        # Allow multiple images to be uploaded
        images: [],
        # Permit nested attributes for variants and images (for updates/ordering/primary)
        product_variants_attributes: [:id, :name, :sku, :price_modifier, :stock_quantity, :_destroy],
        images_attributes: [:id, :primary, :position, :_destroy],
        # Image crop data (hash keyed by attachment ID)
        images_crop_data: {}
      )
    end

    def product_params_without_images
      product_params.except(:images)
    end

    def handle_image_updates
      new_images = params.dig(:product, :images)

      # If there are new images, append them to existing ones
      if new_images.present?
        # Filter out empty uploads
        valid_images = Array(new_images).compact.reject(&:blank?)

        if valid_images.any?
          @product.images.attach(valid_images)

          # Check for attachment errors
          if @product.images.any? { |img| !img.persisted? }
            @product.errors.add(:images, "Failed to attach some images")
            return false
          end
        end
      end

      return true
    rescue => e
      @product.errors.add(:images, "Error processing images: #{e.message}")
      return false
    end

    # Process crop data for individual product images using ImageCroppable concern
    def process_image_crops
      crop_data_hash = params.dig(:product, :images_crop_data)
      return unless crop_data_hash.present?

      process_multi_image_crops(@product, :images, crop_data_hash)
    end
  end
end 