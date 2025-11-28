# frozen_string_literal: true

class Public::EstimatesController < ApplicationController
  skip_before_action :authenticate_user!, only: [:show, :approve, :decline, :request_changes, :download_pdf]
  before_action :find_estimate_by_token
  before_action :set_tenant_from_estimate

  # Token-based show for public access
  def show
    # Mark as viewed if sent (first view)
    if @estimate.sent?
      @estimate.update(status: :viewed, viewed_at: Time.current)
    end

    # Handle payment callbacks
    if params[:payment_success] == 'true'
      flash.now[:success] = "Payment successful! Your estimate has been approved and we'll begin work soon."
    elsif params[:payment_cancelled] == 'true'
      flash.now[:alert] = "Payment was cancelled. Your estimate is still pending approval."
      # Reset status back to viewed if payment was cancelled
      @estimate.update(status: :viewed) if @estimate.pending_payment?
    end
  end

  # Customer approves estimate with signature and optional items selection
  # This initiates the payment flow - approve = pay deposit
  def approve
    # Validate the estimate can be approved
    unless @estimate.can_approve?
      return redirect_to public_estimate_path(token: @estimate.token),
        alert: 'This estimate cannot be approved at this time.'
    end

    # Use the approval service to handle signature, optional items, and payment
    result = EstimateApprovalService.new(
      @estimate,
      signature_data: params[:signature_data],
      signature_name: params[:signature_name],
      selected_optional_items: params[:selected_optional_items] || []
    ).call

    if result[:success]
      # Redirect to Stripe checkout for deposit payment
      redirect_to result[:redirect_url], allow_other_host: true
    else
      flash[:alert] = result[:error]
      redirect_to public_estimate_path(token: @estimate.token)
    end
  end

  def decline
    # Use a transaction with pessimistic locking to prevent race conditions
    success = ActiveRecord::Base.transaction do
      @estimate.lock!

      # Can decline from sent, viewed, or pending_payment states
      unless @estimate.can_decline?
        raise ActiveRecord::Rollback
      end

      @estimate.update!(status: :declined, declined_at: Time.current)
      true
    end

    if success
      EstimateMailer.estimate_declined(@estimate).deliver_later
      redirect_to public_estimate_path(token: @estimate.token),
        notice: 'You have declined this estimate.'
    else
      redirect_to public_estimate_path(token: @estimate.token),
        alert: 'This estimate cannot be declined.'
    end
  end

  def request_changes
    message = params.fetch(:changes_request, "Customer has requested changes, please review.")

    success = ActiveRecord::Base.transaction do
      @estimate.lock!

      if @estimate.approved? || @estimate.declined? || @estimate.cancelled?
        raise ActiveRecord::Rollback
      end

      true
    end

    if success
      EstimateMailer.request_changes_notification(@estimate, message).deliver_later
      redirect_to public_estimate_path(token: @estimate.token),
        notice: 'Your change request has been sent.'
    else
      redirect_to public_estimate_path(token: @estimate.token),
        alert: 'This estimate cannot be modified.'
    end
  end

  def download_pdf
    if @estimate.pdf.attached?
      redirect_to rails_blob_path(@estimate.pdf, disposition: "attachment")
    else
      redirect_to public_estimate_path(token: @estimate.token),
        alert: 'PDF not yet generated for this estimate.'
    end
  end

  private

  def find_estimate_by_token
    @estimate = Estimate.find_by!(token: params[:token])
  end

  def set_tenant_from_estimate
    ActsAsTenant.current_tenant = @estimate.business if @estimate
  end
end
