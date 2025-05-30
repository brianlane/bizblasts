class CartsController < ApplicationController
  before_action :set_tenant, if: -> { request.subdomain.present? && request.subdomain != 'www' }
  skip_before_action :authenticate_user!

  def show
    puts "DEBUG: CartsController#show called"
    puts "DEBUG: Current tenant: #{ActsAsTenant.current_tenant.inspect}"
    puts "DEBUG: Current request subdomain: #{request.subdomain}"
    @cart = CartManager.new(session).retrieve
    puts "DEBUG: Cart content: #{@cart.inspect}"
    
    # If we're in a test environment and the cart is empty but should have items, log it
    if Rails.env.test? && session[:cart].present? && @cart.empty?
      puts "DEBUG: Session has cart items but @cart is empty!"
      puts "DEBUG: Session cart: #{session[:cart]}"
    end
  end
end 