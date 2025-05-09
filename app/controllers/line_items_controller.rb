class LineItemsController < ApplicationController
  before_action :set_tenant, if: -> { request.subdomain.present? && request.subdomain != 'www' }
  skip_before_action :authenticate_user!

  def create
    CartManager.new(session).add(params[:product_variant_id], params[:quantity].to_i)
    
    respond_to do |format|
      format.html { 
        flash[:notice] = "Item added to cart."
        redirect_to cart_path 
      }
      format.json { head :ok }
      format.js { head :ok }
    end
  end

  def update
    CartManager.new(session).update(params[:id], params[:quantity].to_i)
    
    respond_to do |format|
      format.html { 
        flash[:notice] = "Quantity updated."
        redirect_to cart_path 
      }
      format.json { head :ok }
      format.js { head :ok }
    end
  end

  def destroy
    CartManager.new(session).remove(params[:id])
    
    respond_to do |format|
      format.html { 
        flash[:notice] = "Item removed from cart."
        redirect_to cart_path 
      }
      format.json { head :ok }
      format.js { head :ok }
    end
  end
end 