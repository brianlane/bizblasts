class ProductsController < ApplicationController
  # Use ApplicationController's tenant setup for all host types (subdomain, custom domain, main domain)
  # before_action :set_tenant is already defined globally, so no need to redefine it here.
  include BusinessAccessProtection
  skip_before_action :authenticate_user!

  def index
    @business = current_tenant
    
    # Check if business has any visible products first
    visible_products = @business.products.active.where(product_type: [:standard, :mixed])
                                .select(&:visible_to_customers?)
    
    # If no visible products, redirect to home with a message
    if visible_products.empty?
      redirect_to tenant_root_path, notice: "No products are currently available. Please check back later!"
      return
    end
    
    # Build the ActiveRecord relation for products that are visible to customers
    # We need to get the IDs of visible products and use them in a proper AR query
    visible_product_ids = visible_products.map(&:id)
    base_scope = @business.products.where(id: visible_product_ids)
    
    @q = base_scope.ransack(params[:q])
    result = @q.result(distinct: true).positioned

    per_page = Kaminari.config.default_per_page
    if params[:q].blank? && result.count > per_page
      min_id = result.minimum(:id) || 0
      threshold = min_id + per_page - 1
      result = result.where("#{result.klass.table_name}.id > ?", threshold)
    end

    @products = result.page(params[:page])
  end

  def show
    @product = Product.find(params[:id])
    
    if params[:variant_id].present?
      @variant = @product.product_variants.find_by(id: params[:variant_id])
      if @variant.nil?
        flash[:alert] = "Variant not found"
        redirect_to product_path(@product) and return
      end
    else
      @variant = @product.product_variants.first
    end
    
    @images = @product.images.ordered
  end
end 