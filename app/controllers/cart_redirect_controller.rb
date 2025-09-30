# frozen_string_literal: true

# Controller to handle cart access on main domain
# Since carts are business-specific, this redirects users to the appropriate business domain
class CartRedirectController < ApplicationController
  skip_before_action :authenticate_user!

  def show
    # Check if there's a cart in the session
    cart_data = session[:cart]

    if cart_data.blank? || cart_data.empty?
      # No cart, redirect to dashboard or home
      if user_signed_in?
        redirect_to dashboard_path, notice: 'Your cart is empty.'
      else
        redirect_to root_path, notice: 'Your cart is empty.'
      end
      return
    end

    # Find which business the cart belongs to by checking product variants
    variant_ids = cart_data.keys

    # Query without tenant scope to find the business
    business = find_business_for_cart_items(variant_ids)

    if business.nil?
      # Can't find business, clear invalid cart
      session[:cart] = {}
      redirect_to root_path, alert: 'Your cart contained invalid items and has been cleared.'
      return
    end

    # Build the cart URL on the business's domain
    cart_url = build_business_cart_url(business)

    Rails.logger.info "[CartRedirect] Redirecting user to cart on business domain: #{cart_url}"

    redirect_to cart_url, allow_other_host: true
  end

  private

  def find_business_for_cart_items(variant_ids)
    return nil if variant_ids.blank?

    # Query all product variants without tenant scope to find all businesses
    variants = ProductVariant.unscoped.includes(:product => :business).where(id: variant_ids)
    return nil if variants.empty?

    # Group variants by business and log for debugging
    variants_by_business = variants.group_by { |v| v.product.business }

    if variants_by_business.size > 1
      Rails.logger.info "[CartRedirect] Cart contains items from #{variants_by_business.size} businesses: #{variants_by_business.keys.map(&:name).join(', ')}"
    end

    # Return the first business (preserves existing redirect behavior)
    # All cart items will be preserved and accessible on the business domain
    variants_by_business.keys.first
  end

  def build_business_cart_url(business)
    # Determine the appropriate domain for the business
    if business.host_type_custom_domain? && business.custom_domain_allow?
      # Use custom domain
      protocol = Rails.env.production? ? 'https://' : 'http://'
      canonical_host = business.www_canonical_preference? ? "www.#{business.hostname}" : business.hostname
      "#{protocol}#{canonical_host}/cart"
    else
      # Use subdomain
      if Rails.env.production?
        "https://#{business.hostname}.bizblasts.com/cart"
      elsif Rails.env.development?
        port = request.port unless [80, 443].include?(request.port)
        port_str = port ? ":#{port}" : ""
        "#{request.protocol}#{business.hostname}.lvh.me#{port_str}/cart"
      else
        # Test environment
        "http://#{business.hostname}.example.com/cart"
      end
    end
  end
end