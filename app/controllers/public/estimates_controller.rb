# frozen_string_literal: true

class Public::EstimatesController < ApplicationController
  skip_before_action :authenticate_user!, only: [:show, :approve, :decline, :request_changes]
  before_action :find_estimate_by_token, only: [:show, :approve, :decline, :request_changes]
  before_action :set_tenant_from_estimate, only: [:show, :approve, :decline, :request_changes]
  before_action :authenticate_user!, only: [:index]

  # Client portal index
  def index
    @estimates = Estimate.where(tenant_customer: current_user)
  end

  # Token-based show for public access
  def show
    @estimate.viewed! if @estimate.sent? || @estimate.viewed?
  end

  # Customer approves estimate and initiates deposit payment if needed
  def approve
    # Do not allow re-approving declined or cancelled estimates
    if @estimate.declined? || @estimate.cancelled?
      return redirect_to tenant_estimate_path(@estimate.token), alert: 'This estimate cannot be approved.'
    end

    # Approve the estimate
    @estimate.update!(status: :approved, approved_at: Time.current)
    EstimateMailer.estimate_approved(@estimate).deliver_later

    # Create booking and invoice
    booking_attrs = {
      business: @estimate.business,
      tenant_customer: @estimate.tenant_customer,
      start_time: @estimate.proposed_start_time || Time.current,
      end_time: (@estimate.proposed_start_time || Time.current) + 1.hour,
      service: @estimate.estimate_items.first&.service,
      quantity: @estimate.estimate_items.sum(&:qty),
      amount: @estimate.subtotal,
      original_amount: @estimate.subtotal,
      discount_amount: 0,
      status: :pending
    }
    booking = Booking.new(booking_attrs)
    booking.save!(validate: false)
    @estimate.update!(booking: booking)
    invoice = Invoice.create_from_estimate(@estimate)

    # Redirect based on deposit requirement
    if @estimate.required_deposit.to_f > 0
      redirect_to new_tenant_payment_path(invoice_id: invoice.id)
    else
      redirect_to tenant_estimate_path(@estimate.token), notice: 'Estimate approved. No deposit was required.'
    end
  end

  def decline
    @estimate.update(status: :declined, declined_at: Time.current)
    EstimateMailer.estimate_declined(@estimate).deliver_later
    redirect_to tenant_estimate_path(@estimate.token), notice: 'You have declined this estimate.'
  end

  def request_changes
    message = params.fetch(:changes_request, "Customer has requested changes, please review.")
    EstimateMailer.request_changes_notification(@estimate, message).deliver_later
    redirect_to tenant_estimate_path(@estimate.token), notice: 'Your change request has been sent.'
  end

  private

  def find_estimate_by_token
    @estimate = Estimate.find_by!(token: params[:token])
  end

  def set_tenant_from_estimate
    ActsAsTenant.current_tenant = @estimate.business if @estimate
  end
end 