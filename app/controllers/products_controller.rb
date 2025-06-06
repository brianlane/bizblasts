class ProductsController < ApplicationController
  skip_before_action :authenticate_user!

  def index
    @business = current_tenant
    # Base scope for products
    base_scope = @business.products.active.where(product_type: [:standard, :mixed])
    @q = base_scope.ransack(params[:q])
    result = @q.result(distinct: true).order(:id)

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