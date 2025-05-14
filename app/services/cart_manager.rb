class CartManager
  def initialize(session)
    @session = session
    @session[:cart] ||= {}
  end

  def add(product_variant_id, quantity)
    puts "DEBUG: CartManager#add called with variant_id: #{product_variant_id}, quantity: #{quantity}"
    product_variant_id = product_variant_id.to_s
    @session[:cart][product_variant_id] ||= 0
    @session[:cart][product_variant_id] += quantity
    puts "DEBUG: Cart content after add: #{@session[:cart]}"
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
    puts "DEBUG: CartManager#retrieve called"
    puts "DEBUG: Current tenant in retrieve: #{ActsAsTenant.current_tenant&.subdomain}"
    # Returns a hash of ProductVariant objects and their quantities
    variant_ids = @session[:cart].keys
    puts "DEBUG: Variant IDs in session: #{variant_ids}"
    variants = ProductVariant.where(id: variant_ids)
    puts "DEBUG: Variants found by query: #{variants.map(&:id)}"
    variants.map { |variant| [variant, @session[:cart][variant.id.to_s]] }.to_h
  end
end 