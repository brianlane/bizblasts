module BusinessManager
  class ProductsController < BaseController # Inherit from your base controller for this namespace
    before_action :set_product, only: [:show, :edit, :update, :destroy, :update_position, :move_up, :move_down]

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
        redirect_to business_manager_product_path(@product), notice: 'Product was successfully created.'
      else
        flash.now[:alert] = @product.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
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
        redirect_to business_manager_product_path(@product), notice: 'Product was successfully updated.'
      else
        flash.now[:alert] = @product.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
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
        render json: { status: 'error', message: 'Failed to update product position' }, status: :unprocessable_entity
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
          format.json { render json: { status: 'error', message: 'Failed to move product up' }, status: :unprocessable_entity }
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
          format.json { render json: { status: 'error', message: 'Failed to move product down' }, status: :unprocessable_entity }
          format.html { redirect_to business_manager_products_path, alert: 'Failed to move product down' }
        end
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
        add_on_service_ids: [], 
        # Allow multiple images to be uploaded
        images: [], 
        # Permit nested attributes for variants and images (for updates/ordering/primary)
        product_variants_attributes: [:id, :name, :sku, :price_modifier, :stock_quantity, :options, :_destroy],
        images_attributes: [:id, :primary, :position, :_destroy]
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
  end
end 