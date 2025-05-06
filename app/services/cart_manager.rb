class CartManager
  def initialize(session)
    @session = session
    @session[:cart] ||= {}
  end

  def add(product_variant_id, quantity)
    product_variant_id = product_variant_id.to_s
    @session[:cart][product_variant_id] ||= 0
    @session[:cart][product_variant_id] += quantity
  end

  def update(product_variant_id, quantity)
    product_variant_id = product_variant_id.to_s
    if quantity > 0
      @session[:cart][product_variant_id] = quantity
    else
      @session[:cart].delete(product_variant_id)
    end
  end

  def remove(product_variant_id)
    product_variant_id = product_variant_id.to_s
    @session[:cart].delete(product_variant_id)
  end

  def retrieve
    # Returns a hash of ProductVariant objects and their quantities
    variants = ProductVariant.where(id: @session[:cart].keys)
    variants.map { |variant| [variant, @session[:cart][variant.id.to_s]] }.to_h
  end
end 