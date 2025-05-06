class LineItemsController < ApplicationController
  before_action :set_tenant, if: -> { request.subdomain.present? && request.subdomain != 'www' }
  skip_before_action :authenticate_user!

  def create
    CartManager.new(session).add(params[:product_variant_id], params[:quantity].to_i)
    head :ok
  end

  def update
    CartManager.new(session).update(params[:id], params[:quantity].to_i)
    head :ok
  end

  def destroy
    CartManager.new(session).remove(params[:id])
    head :ok
  end
end 