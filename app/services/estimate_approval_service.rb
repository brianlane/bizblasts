# Handles the estimate approval flow where approve = pay deposit
# This service coordinates signature capture, optional item selection,
# PDF generation, and payment initiation via Stripe
#
# Flow:
# 1. Customer views estimate
# 2. Customer selects/declines optional items
# 3. Customer signs estimate
# 4. Customer clicks "Approve" → redirect to Stripe
# 5. Payment failed/cancelled → status stays pending_payment
# 6. Payment successful (webhook) → status becomes approved
#
class EstimateApprovalService
  def initialize(estimate, params = {})
    @estimate = estimate
    @signature_data = params[:signature_data]
    @signature_name = params[:signature_name]
    @selected_optional_items = params[:selected_optional_items] || []
  end

  def call
    # Step 1: Validate estimate can be approved
    unless @estimate.can_approve?
      return failure_result("Estimate cannot be approved in current state (#{@estimate.status})")
    end

    # Step 2: Validate signature
    unless @signature_data.present? && @signature_name.present?
      return failure_result("Signature is required to approve this estimate")
    end

    # Wrap all database operations in a transaction to ensure atomicity
    # If any step fails, all changes are rolled back and estimate stays in original state
    result = nil
    ActiveRecord::Base.transaction do
      # Step 3: Process optional items selection (mark non-selected as declined)
      process_optional_items_selection

      document = prepare_client_document

      # Step 4: Save signature and move to pending_payment status
      @estimate.update!(
        signature_data: @signature_data,
        signature_name: @signature_name,
        signed_at: Time.current,
        status: :pending_payment
      )

      ClientDocuments::SignatureService.new(document).capture!(
        signer_name: @signature_name,
        signer_email: @estimate.customer_email,
        signature_data: @signature_data
      )
      ClientDocuments::WorkflowService.new(document).mark_signature_captured!

      # Step 5: Recalculate totals with final optional items selection
      @estimate.recalculate_totals!
      document.update!(
        deposit_amount: @estimate.deposit_amount,
        payment_required: @estimate.deposit_amount.to_f.positive?
      )

      # Step 6: Generate PDF with signature
      EstimatePdfGenerator.new(@estimate).generate

      # Step 7: Create booking and invoice from estimate
      booking = EstimateToBookingService.new(@estimate).call
      unless booking.present?
        raise StandardError, "Failed to create booking from estimate"
      end

      # Step 8: Get or create invoice for payment
      invoice = booking.reload.invoice
      unless invoice.present?
        raise StandardError, "Failed to create invoice for payment"
      end
      document.update!(invoice: invoice)

      # Step 9: Create Stripe checkout session for deposit payment
      checkout_result = create_checkout_session(document)
      if checkout_result[:url].blank?
        raise StandardError, checkout_result[:error] || "Failed to create payment session"
      end

      # Step 10: Update estimate with checkout session tracking
      @estimate.update!(
        checkout_session_id: checkout_result[:session_id],
        payment_intent_id: checkout_result[:payment_intent_id]
      )

      # Set result for return after transaction commits
      result = success_result(
        redirect_url: checkout_result[:url],
        invoice: invoice,
        booking: booking
      )
    end

    result
  rescue => e
    Rails.logger.error "[EstimateApprovalService] Error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    failure_result("An error occurred: #{e.message}")
  end

  private

  def prepare_client_document
    document = @estimate.ensure_client_document!
    ClientDocuments::WorkflowService.new(document).mark_pending_signature!
    document
  end

  def process_optional_items_selection
    return unless @estimate.has_optional_items?

    # All optional items not in selected list are marked as declined
    # All items stay in the estimate, but declined ones are excluded from totals
    @estimate.estimate_items.optional_items.each do |item|
      if @selected_optional_items.include?(item.id.to_s) || @selected_optional_items.include?(item.id)
        item.update!(customer_selected: true, customer_declined: false)
      else
        # Mark as declined - item stays but is excluded from totals
        item.update!(customer_selected: false, customer_declined: true)
      end
    end
  end

  def create_checkout_session(document)
    payment_amount = @estimate.deposit_amount

    if payment_amount < 0.50
      raise ArgumentError, "Payment amount must be at least $0.50 USD. Current amount: $#{payment_amount}"
    end

    # Build success/cancel URLs
    success_url = build_success_url
    cancel_url = build_cancel_url

    result = ClientDocuments::DepositService.new(document).initiate_checkout!(
      success_url: success_url,
      cancel_url: cancel_url
    )

    session = result[:session]
    {
      success: true,
      session_id: session.id,
      payment_intent_id: session.payment_intent,
      url: session.url
    }
  rescue ArgumentError => e
    # Handle minimum amount validation
    { success: false, error: e.message }
  rescue Stripe::StripeError => e
    Rails.logger.error "[EstimateApprovalService] Stripe error: #{e.message}"
    { success: false, error: "Payment processing error: #{e.message}" }
  rescue => e
    Rails.logger.error "[EstimateApprovalService] Checkout session error: #{e.message}"
    { success: false, error: "Failed to create payment session" }
  end

  def build_success_url
    host = ENV.fetch('APP_HOST', 'localhost:3000')
    protocol = Rails.env.production? ? 'https' : 'http'

    "#{protocol}://#{host}/estimates/#{@estimate.token}?payment_success=true"
  end

  def build_cancel_url
    host = ENV.fetch('APP_HOST', 'localhost:3000')
    protocol = Rails.env.production? ? 'https' : 'http'

    "#{protocol}://#{host}/estimates/#{@estimate.token}?payment_cancelled=true"
  end

  def success_result(data)
    { success: true }.merge(data)
  end

  def failure_result(message)
    { success: false, error: message }
  end
end

