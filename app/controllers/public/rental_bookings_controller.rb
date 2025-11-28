# frozen_string_literal: true

module Public
  class RentalBookingsController < ApplicationController
    before_action :set_rental_booking, only: [:show, :pay_deposit, :deposit_success, :deposit_cancel, :confirmation]
    before_action :authorize_booking_access!, only: [:show, :confirmation]
    
    # GET /rental_bookings/:id
    def show
      # Authorization handled by before_action :authorize_booking_access!
    end
    
    # GET /rental_bookings/:id/pay_deposit
    def pay_deposit
      unless @rental_booking.status_pending_deposit?
        redirect_to rental_booking_path(@rental_booking), 
                    notice: 'Deposit has already been paid.'
        return
      end
      
      # Create Stripe checkout session for deposit
      checkout_session = StripeService.create_rental_deposit_checkout_session(
        rental_booking: @rental_booking,
        success_url: deposit_success_rental_booking_url(@rental_booking),
        cancel_url: deposit_cancel_rental_booking_url(@rental_booking)
      )
      
      redirect_to checkout_session.url, allow_other_host: true
    rescue => e
      Rails.logger.error("[RentalBookingsController] Failed to create Stripe session: #{e.message}")
      redirect_to rental_booking_path(@rental_booking), 
                  alert: 'Unable to process payment at this time. Please try again later.'
    end
    
    # GET /rental_bookings/:id/deposit_success
    def deposit_success
      # Mark deposit as paid (webhook will also handle this, but update UI immediately)
      if @rental_booking.status_pending_deposit?
        @rental_booking.mark_deposit_paid!(payment_intent_id: params[:payment_intent])
      end
      
      # Show confirmation page
    end
    
    # GET /rental_bookings/:id/deposit_cancel
    def deposit_cancel
      # Return to booking page - no status change needed
      redirect_to rental_booking_path(@rental_booking), 
                  notice: 'Payment was cancelled. You can try again when ready.'
    end
    
    # GET /rental_bookings/:id/confirmation
    def confirmation
      # Authorization handled by before_action :authorize_booking_access!
      # @rental_booking set by before_action :set_rental_booking
    end
    
    private
    
    def set_rental_booking
      @rental_booking = if params[:token].present?
        current_tenant.rental_bookings.find_by!(guest_access_token: params[:token])
      else
        current_tenant.rental_bookings.find(params[:id])
      end
    end
    
    def authorized_to_view?
      return true if params[:token].present? && @rental_booking.guest_access_token == params[:token]
      return true if user_signed_in? && @rental_booking.tenant_customer&.email == current_user.email
      false
    end
    
    def authorize_booking_access!
      unless authorized_to_view?
        redirect_to root_path, alert: 'You are not authorized to view this booking.'
      end
    end
  end
end

