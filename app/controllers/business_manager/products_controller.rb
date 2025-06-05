module BusinessManager
  class ProductsController < BaseController # Inherit from your base controller for this namespace
    before_action :set_product, only: [:show, :edit, :update, :destroy]

    # GET /manage/products
    def index
      @products = @current_business.products.includes(:category, :product_variants).order(:name)
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
        handle_image_attachments # Handle potential primary/ordering updates if needed
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
      if @product.update(product_params)
        handle_image_attachments # Handle potential primary/ordering updates if needed
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
                   .includes(:category, :product_variants, images_attachments: :blob)
                   .find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to business_manager_products_path, alert: 'Product not found.'
    end

    def product_params
      params.require(:product).permit(
        :name, :description, :price, :active, :featured, :category_id, :product_type,
        :stock_quantity, # If product can be sold without variants
        add_on_service_ids: [], 
        # Allow multiple images to be uploaded
        images: [], 
        # Permit nested attributes for variants and images (for updates/ordering/primary)
        product_variants_attributes: [:id, :name, :sku, :price_modifier, :stock_quantity, :options, :_destroy],
        images_attributes: [:id, :primary, :position, :_destroy]
      )
    end

    # Optional: Handle image primary/ordering if form submits `images_attributes`
    def handle_image_attachments
      # The `images: []` param is already handled automatically by Rails during save/update
      # Only handle images_attributes for managing existing images (primary, position, deletion)
      # No need to manually attach new images here as Rails does this automatically
    end
  end
end 