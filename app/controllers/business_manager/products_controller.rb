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
      # Build at least one variant for the nested form if products require variants
      @product.product_variants.build if @product.product_variants.empty?
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
      # Ensure variants are built if none exist for the form
      @product.product_variants.build if @product.product_variants.empty?
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
      # This logic depends heavily on how your form submits image data (e.g., direct uploads vs. using images_attributes for ordering/primary flags)
      
      # Example if using direct `images: []` param for uploads (simple case):
      if params[:product][:images].present?
         params[:product][:images].each do |image|
           @product.images.attach(image)
         end
      end
      
      # If using images_attributes for metadata updates (like ActiveAdmin does):
      # Need to ensure @product.images_attributes= method handles the submitted params correctly.
      # This might already be handled by the model if `images_attributes=` setter exists.
      # If params[:product][:images_attributes] is present, the model's setter should handle it during @product.update/save.
      # No explicit call needed here unless model doesn't have the setter.
    end
  end
end 