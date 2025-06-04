class LineItemsController < ApplicationController
  before_action :set_tenant, if: -> { request.subdomain.present? && request.subdomain != 'www' }
  skip_before_action :authenticate_user!
  
  # Security: Add rate limiting for cart operations (implement with rack-attack)
  # before_action :check_cart_rate_limit

  def create
    # Security: Validate parameters
    product_variant_id = validate_positive_integer(params[:product_variant_id], 'Product variant ID')
    quantity = validate_quantity(params[:quantity])
    
    return if performed? # If validation failed and response was already sent

    CartManager.new(session).add(product_variant_id, quantity)
    
    respond_to do |format|
      format.html { 
        flash[:notice] = "Item added to cart."
        redirect_to cart_path 
      }
      format.json { head :ok }
      format.js { head :ok }
    end
  rescue => e
    Rails.logger.error "[CART] Error adding item to cart: #{e.message}, IP: #{request.remote_ip}"
    handle_cart_error
  end

  def update
    # Security: Validate parameters
    item_id = validate_positive_integer(params[:id], 'Item ID')
    quantity = validate_quantity(params[:quantity])
    
    return if performed? # If validation failed and response was already sent

    CartManager.new(session).update(item_id, quantity)
    
    respond_to do |format|
      format.html { 
        flash[:notice] = "Quantity updated."
        redirect_to cart_path 
      }
      format.json { head :ok }
      format.js { head :ok }
    end
  rescue => e
    Rails.logger.error "[CART] Error updating cart item: #{e.message}, IP: #{request.remote_ip}"
    handle_cart_error
  end

  def destroy
    # Security: Validate parameter
    item_id = validate_positive_integer(params[:id], 'Item ID')
    
    return if performed? # If validation failed and response was already sent

    CartManager.new(session).remove(item_id)
    
    respond_to do |format|
      format.html { 
        flash[:notice] = "Item removed from cart."
        redirect_to cart_path 
      }
      format.json { head :ok }
      format.js { head :ok }
    end
  rescue => e
    Rails.logger.error "[CART] Error removing cart item: #{e.message}, IP: #{request.remote_ip}"
    handle_cart_error
  end

  private

  # Security: Validate positive integer parameters
  def validate_positive_integer(param, param_name)
    unless param.present? && param.to_i > 0
      Rails.logger.warn "[SECURITY] Invalid #{param_name} parameter: #{param}, IP: #{request.remote_ip}"
      respond_to do |format|
        format.html { 
          flash[:alert] = "Invalid #{param_name.downcase}."
          redirect_to cart_path 
        }
        format.json { render json: { error: "Invalid #{param_name.downcase}" }, status: :bad_request }
        format.js { head :bad_request }
      end
      return nil
    end
    param.to_i
  end

  # Security: Validate quantity with reasonable limits
  def validate_quantity(quantity_param)
    quantity = quantity_param.to_i
    
    # Security: Allow 0 (remove item) and prevent negative quantities or extremely large quantities
    if quantity < 0 || quantity > 999
      Rails.logger.warn "[SECURITY] Invalid quantity parameter: #{quantity}, IP: #{request.remote_ip}"
      respond_to do |format|
        format.html { 
          flash[:alert] = "Quantity must be between 0 and 999."
          redirect_to cart_path 
        }
        format.json { render json: { error: "Invalid quantity" }, status: :bad_request }
        format.js { head :bad_request }
      end
      return nil
    end
    
    quantity
  end

  # Security: Consistent error handling
  def handle_cart_error
    respond_to do |format|
      format.html { 
        flash[:alert] = "An error occurred. Please try again."
        redirect_to cart_path 
      }
      format.json { render json: { error: "An error occurred" }, status: :internal_server_error }
      format.js { head :internal_server_error }
    end
  end

  # Security: Rate limiting check (implement with rack-attack gem)
  # def check_cart_rate_limit
  #   # throttle('cart_operations/ip', limit: 30, period: 1.minute) do |req|
  #   #   req.ip if req.controller == 'line_items'
  #   # end
  # end
end 