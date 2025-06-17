module BusinessManager
  class ProductsController < BaseController # Inherit from your base controller for this namespace
    before_action :set_product, only: [:show, :edit, :update, :destroy]

    # GET /manage/products
    def index
      @products = @current_business.products.includes(:product_variants).order(:name)
      # Add pagination if needed: e.g., @products = @products.page(params[:page])
    end

    # GET /manage/products/:id
    def show
      # @product set by before_action
      # No need to load associations here, handled in set_product
    end

    # GET /manage/products/new
    def new
      @product = @current_business.products.new
      # No automatic variant build; variants are opt-in via Add Variant link
    end

    # POST /manage/products
    def create
      @product = @current_business.products.new(product_params)
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

    private

    def set_product
      # Eager load associations needed for show/edit views here
            @product = @current_business.products
        .includes(:product_variants, images_attachments: :blob)
        .find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to business_manager_products_path, alert: 'Product not found.'
    end

    def product_params
      params.require(:product).permit(
        :name, :description, :price, :active, :featured, :product_type, :tips_enabled, :allow_discounts,
        :stock_quantity, # If product can be sold without variants
        :subscription_enabled, :subscription_discount_percentage, :subscription_billing_cycle, :subscription_out_of_stock_action, :allow_customer_preferences,
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