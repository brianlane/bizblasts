# frozen_string_literal: true

class Public::EstimatesController < ApplicationController
  skip_before_action :authenticate_user!, only: [:show, :approve, :decline, :request_changes]
  before_action :find_estimate_by_token, only: [:show, :approve, :decline, :request_changes]
  before_action :set_tenant_from_estimate, only: [:show, :approve, :decline, :request_changes]

  # Token-based show for public access
  def show
    # Mark as viewed if sent (first view) - Rails enum doesn't generate bang methods
    if @estimate.sent?
      @estimate.update(status: :viewed, viewed_at: Time.current)
    end
  end

  # Customer approves estimate and initiates deposit payment if needed
  def approve
    # Use a transaction with pessimistic locking to prevent race conditions
    # Lock the estimate row to ensure only one request can process approval
    booking = ActiveRecord::Base.transaction do
      # Reload and lock the estimate to get the latest status and prevent concurrent modifications
      @estimate.lock!

      # Check status INSIDE the transaction with the locked record
      # This prevents race conditions where two requests both pass the check
      if @estimate.declined? || @estimate.cancelled?
        # Rollback and return early
        raise ActiveRecord::Rollback
      end

      if @estimate.approved?
        # Already approved by another concurrent request
        raise ActiveRecord::Rollback
      end

      # Approve the estimate (still within the lock)
      @estimate.update!(status: :approved, approved_at: Time.current)

      # Use the service object to create booking and invoice
      EstimateToBookingService.new(@estimate).call
    end

    # Check if transaction was rolled back (estimate was already processed)
    if booking.nil?
      if @estimate.reload.approved?
        return redirect_to public_estimate_path(token: @estimate.token), notice: 'This estimate has already been approved.'
      elsif @estimate.declined? || @estimate.cancelled?
        return redirect_to public_estimate_path(token: @estimate.token), alert: 'This estimate cannot be approved.'
      else
        return redirect_to public_estimate_path(token: @estimate.token), alert: 'Could not approve estimate.'
      end
    end

    # Send approval email after successful transaction
    EstimateMailer.estimate_approved(@estimate).deliver_later

    # Redirect based on deposit requirement
    if @estimate.required_deposit.to_f > 0
      invoice = booking.invoice
      if invoice
        redirect_to new_payment_path(invoice_id: invoice.id)
      else
        redirect_to public_estimate_path(token: @estimate.token), notice: 'Estimate approved. No deposit was required.'
      end
    else
      redirect_to public_estimate_path(token: @estimate.token), notice: 'Estimate approved. No deposit was required.'
    end
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Error approving estimate: #{e.message}"
    redirect_to public_estimate_path(token: @estimate.token), alert: "Could not approve estimate: #{e.message}"
  rescue StandardError => e
    Rails.logger.error "Unexpected error during estimate approval: #{e.message}"
    redirect_to public_estimate_path(token: @estimate.token), alert: "An unexpected error occurred: #{e.message}"
  end

  def decline
    if @estimate.approved? || @estimate.declined? || @estimate.cancelled?
      return redirect_to public_estimate_path(token: @estimate.token), alert: 'This estimate cannot be declined.'
    end

    @estimate.update!(status: :declined, declined_at: Time.current)
    EstimateMailer.estimate_declined(@estimate).deliver_later
    redirect_to public_estimate_path(token: @estimate.token), notice: 'You have declined this estimate.'
  end

  def request_changes
    if @estimate.approved? || @estimate.declined? || @estimate.cancelled?
      return redirect_to public_estimate_path(token: @estimate.token), alert: 'This estimate cannot be modified.'
    end

    message = params.fetch(:changes_request, "Customer has requested changes, please review.")
    EstimateMailer.request_changes_notification(@estimate, message).deliver_later
    redirect_to public_estimate_path(token: @estimate.token), notice: 'Your change request has been sent.'
  end

  private

  def find_estimate_by_token
    @estimate = Estimate.find_by!(token: params[:token])
  end

  def set_tenant_from_estimate
    ActsAsTenant.current_tenant = @estimate.business if @estimate
  end
end 