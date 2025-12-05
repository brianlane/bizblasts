# frozen_string_literal: true

module Public
  class RentalBookingsController < ApplicationController
    before_action :set_rental_booking, only: [:show, :pay_deposit, :submit_deposit, :deposit_success, :deposit_cancel, :confirmation]
    before_action :authorize_booking_access!, only: [:show, :pay_deposit, :submit_deposit, :deposit_success, :deposit_cancel, :confirmation]
    
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

      @client_document = @rental_booking.ensure_client_document!
    end

    # POST /rental_bookings/:id/submit_deposit
    def submit_deposit
      unless @rental_booking.status_pending_deposit?
        redirect_to rental_booking_path(@rental_booking),
                    notice: 'Deposit has already been paid.'
        return
      end

      unless params[:signature_data].present? && params[:signature_name].present?
        flash.now[:alert] = 'Signature is required to continue.'
        @client_document = @rental_booking.ensure_client_document!
        render :pay_deposit, status: :unprocessable_content
        return
      end

      @client_document = @rental_booking.ensure_client_document!
      ClientDocuments::SignatureService.new(@client_document).capture!(
        signer_name: params[:signature_name],
        signer_email: @rental_booking.customer_email,
        signature_data: params[:signature_data],
        request: request
      )
      ClientDocuments::WorkflowService.new(@client_document).mark_signature_captured!

      result = ClientDocuments::DepositService.new(@client_document).initiate_checkout!(
        success_url: deposit_success_rental_booking_url(@rental_booking, token: params[:token]),
        cancel_url: deposit_cancel_rental_booking_url(@rental_booking, token: params[:token])
      )

      redirect_to result[:session].url, allow_other_host: true
    rescue => e
      Rails.logger.error("[RentalBookingsController] Failed to process deposit submission: #{e.message}")
      redirect_to rental_booking_path(@rental_booking, token: params[:token]),
                  alert: 'Unable to process payment at this time. Please try again later.'
    end
    
    # GET /rental_bookings/:id/deposit_success
    def deposit_success
      # Note: Do NOT change booking status here. Status changes should only happen
      # via verified Stripe webhooks to prevent unauthorized marking of bookings as paid.
      # This action only shows the success UI - the webhook will update the actual status.
      #
      # The booking may still show as pending_deposit until the webhook processes,
      # which typically happens within seconds.
      
      # Show confirmation page
    end
    
    # GET /rental_bookings/:id/deposit_cancel
    def deposit_cancel
      # Return to booking page - no status change needed
      redirect_path = if params[:token].present?
        rental_booking_path(@rental_booking, token: params[:token])
      else
        rental_booking_path(@rental_booking)
      end

      redirect_to redirect_path, notice: 'Payment was cancelled. You can try again when ready.'
    end
    
    # GET /rental_bookings/:id/confirmation
    def confirmation
      # Authorization handled by before_action :authorize_booking_access!
      # @rental_booking set by before_action :set_rental_booking
    end
    
    private
    
    def set_rental_booking
      scope = current_tenant.rental_bookings.includes(:product, :tenant_customer, :location)

      @rental_booking = if params[:token].present?
        scope.find_by!(guest_access_token: params[:token])
      else
        scope.find(params[:id])
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

