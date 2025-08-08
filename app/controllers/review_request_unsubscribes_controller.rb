# frozen_string_literal: true

# ReviewRequestUnsubscribesController handles unsubscribing from review request emails
# Uses signed tracking tokens to identify and suppress future review requests
class ReviewRequestUnsubscribesController < ApplicationController
  skip_before_action :authenticate_user! # Allow public access via signed token
  skip_before_action :verify_authenticity_token # Skip CSRF for GET requests with tokens
  
  # Handle unsubscribe request via GET with signed token
  def show
    @token = params[:token]
    
    # Verify and decode the signed token
    token_data = verify_tracking_token(@token)
    
    if token_data
      @business = Business.find_by(id: token_data[:business_id])
      @customer = @business&.tenant_customers&.find_by(id: token_data[:customer_id])
      @booking = @business&.bookings&.find_by(id: token_data[:booking_id]) if token_data[:booking_id]
      @order = @business&.orders&.find_by(id: token_data[:order_id]) if token_data[:order_id]
      @invoice = @business&.invoices&.find_by(id: token_data[:invoice_id]) if token_data[:invoice_id]
      
      if @business && @customer
        # Mark the specific booking/order/invoice as unsubscribed from review requests
        mark_unsubscribed(token_data)
        @success = true
        @message = "You have been successfully unsubscribed from review requests for this service."
      else
        @success = false
        @message = "Invalid or expired unsubscribe link."
      end
    else
      @success = false
      @message = "Invalid or expired unsubscribe link."
    end
    
    render 'show', layout: 'public'
  rescue => e
    Rails.logger.error "[ReviewRequestUnsubscribes] Error processing unsubscribe: #{e.message}"
    @success = false
    @message = "An error occurred while processing your request."
    render 'show', layout: 'public'
  end
  
  private
  
  # Verify the signed tracking token
  def verify_tracking_token(token)
    return nil unless token.present?
    
    # Use Rails message verifier to verify and decode the signed token
    verifier = Rails.application.message_verifier('review_request_tracking')
    verifier.verified(token)
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end
  
  # Mark the specific booking/order/invoice as unsubscribed from review requests
  def mark_unsubscribed(token_data)
    # Create a record to track the unsubscribe
    # Using a simple approach: add a column to track review request suppression
    
    if token_data[:booking_id] && @booking
      # Add review_request_suppressed flag to booking
      @booking.update_column(:review_request_suppressed, true) if @booking.respond_to?(:review_request_suppressed)
    end
    
    if token_data[:order_id] && @order
      # Add review_request_suppressed flag to order
      @order.update_column(:review_request_suppressed, true) if @order.respond_to?(:review_request_suppressed)
    end
    
    if token_data[:invoice_id] && @invoice
      # Add review_request_suppressed flag to invoice
      @invoice.update_column(:review_request_suppressed, true) if @invoice.respond_to?(:review_request_suppressed)
    end
    
    Rails.logger.info "[ReviewRequestUnsubscribes] Suppressed review requests for customer #{@customer.id} in business #{@business.id}"
  end
end