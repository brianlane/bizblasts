class CartsController < ApplicationController
  before_action :set_tenant, if: -> { request.subdomain.present? && request.subdomain != 'www' }
  include BusinessAccessProtection
  skip_before_action :authenticate_user!

  def show
    @cart = CartManager.new(session).retrieve
  end
end 