# frozen_string_literal: true

class StripeService
  # This service handles integration with the Stripe payment gateway

  # Configure API key for all Stripe calls
  def self.configure_stripe_api_key
    stripe_credentials = Rails.application.credentials.stripe || {}
    Stripe.api_key = stripe_credentials[:secret_key] || ENV['STRIPE_SECRET_KEY']
  end

  # Enhanced wrapper for Stripe API calls with error monitoring
  # Useful during IP transition to identify connectivity issues
  def self.with_stripe_error_monitoring(operation_name)
    configure_stripe_api_key
    start_time = Time.current

    begin
      result = yield
      duration = Time.current - start_time
      Rails.logger.debug "[StripeService] #{operation_name} successful (#{duration.round(3)}s)"
      result
    rescue Stripe::AuthenticationError => e
      Rails.logger.error "[StripeService] AUTHENTICATION ERROR in #{operation_name}: #{e.message}"
      Rails.logger.error "[StripeService] This may indicate IP allowlist issues after Render IP change"
      raise
    rescue Stripe::PermissionError => e
      Rails.logger.error "[StripeService] PERMISSION ERROR in #{operation_name}: #{e.message}"
      Rails.logger.error "[StripeService] This may indicate IP allowlist issues after Render IP change"
      raise
    rescue Stripe::APIConnectionError => e
      Rails.logger.error "[StripeService] CONNECTION ERROR in #{operation_name}: #{e.message}"
      Rails.logger.error "[StripeService] This may indicate network/IP connectivity issues"
      raise
    rescue => e
      duration = Time.current - start_time
      Rails.logger.error "[StripeService] #{operation_name} failed after #{duration.round(3)}s: #{e.class.name} - #{e.message}"
      raise
    end
  end
  
  def self.stripe_configured?
    stripe_credentials = Rails.application.credentials.stripe || {}
    (stripe_credentials[:secret_key] || ENV['STRIPE_SECRET_KEY']).present?
  end

  # Create a Stripe Connect Express account for a business
  def self.create_connect_account(business)
    configure_stripe_api_key
    account = Stripe::Account.create(
      type: 'standard',
      country: 'US',
      email: business.email,
      capabilities: {
        card_payments: { requested: true },
        transfers: { requested: true }
      },
      metadata: { business_id: business.id }
    )
    business.update!(stripe_account_id: account.id)
    account
  end

  # Generate onboarding link for a Stripe Connect account
  def self.create_onboarding_link(business, refresh_url:, return_url:)
    configure_stripe_api_key
    Stripe::AccountLink.create(
      account: business.stripe_account_id,
      refresh_url: refresh_url,
      return_url: return_url,
      type: 'account_onboarding'
    )
  end

  # Check if onboarding is complete
  def self.check_onboarding_status(business)
    configure_stripe_api_key
    account = Stripe::Account.retrieve(business.stripe_account_id)
    account.details_submitted
  end

  # Create a Stripe subscription for the business
  def self.create_subscription(business, price_id)
    configure_stripe_api_key
    customer = ensure_stripe_customer_for_business(business)
    Stripe::Subscription.create(
      customer: customer.id,
      items: [{ price: price_id }]
    )
  end

  # Handle subscription failures
  def self.handle_subscription_suspension(stripe_sub)
    business = Business.find_by(stripe_customer_id: stripe_sub.customer)
    return unless business
    record = business.subscription
    record&.update!(status: 'suspended')
  end

  # Create a Stripe Checkout session for booking payment (booking created after payment)
  def self.create_payment_checkout_session_for_booking(invoice:, booking_data:, success_url:, cancel_url:)
    configure_stripe_api_key
    business = invoice.business
    tenant_customer = invoice.tenant_customer

    total_amount = invoice.total_amount.to_f
    
    # Stripe requires a minimum charge amount of $0.50 USD
    if total_amount < 0.50
      raise ArgumentError, "Payment amount must be at least $0.50 USD. Current amount: $#{total_amount}"
    end
    
    amount_cents = (total_amount * 100).to_i
    platform_fee_cents = calculate_platform_fee_cents(amount_cents, business)

    # Prepare session parameters
    session_params = {
      payment_method_types: ['card'],
      line_items: [{
        price_data: {
          currency: 'usd',
          product_data: {
            name: "Service Booking",
            description: "Payment for #{business.name}"
          },
          unit_amount: amount_cents
        },
        quantity: 1
      }],
      mode: 'payment',
      success_url: success_url,
      cancel_url: cancel_url,
      customer_creation: 'always', # Let Stripe create the customer during checkout
      customer_email: tenant_customer.email, # Pre-fill email
      payment_intent_data: {
        application_fee_amount: platform_fee_cents,
        metadata: { 
          business_id: business.id, 
          tenant_customer_id: tenant_customer.id,
          booking_type: 'service_booking'
        }
      },
      metadata: { 
        business_id: business.id, 
        tenant_customer_id: tenant_customer.id,
        booking_type: 'service_booking',
        booking_data: booking_data.to_json
      }
    }
    
    # Ensure we have a valid Stripe customer for the tenant (on connected account)
    stripe_customer = ensure_stripe_customer_for_tenant(tenant_customer, business)
    if stripe_customer
      session_params[:customer] = stripe_customer.id
      session_params.delete(:customer_creation) # Don't create new customer if using existing
      session_params.delete(:customer_email) # Don't pre-fill if using existing customer
    end

    # Create the checkout session with booking data in metadata (direct charge on connected account)
    session = Stripe::Checkout::Session.create(session_params, {
      stripe_account: business.stripe_account_id
    })

    # Don't create payment record here - it will be created by the webhook
    # when the payment is actually processed by Stripe
    { session: session, payment: nil }
  end

  # Create a Stripe Checkout session for invoice payment
  def self.create_payment_checkout_session(invoice:, success_url:, cancel_url:)
    configure_stripe_api_key
    business = invoice.business
    tenant_customer = invoice.tenant_customer

    total_amount = invoice.total_amount.to_f
    
    # Stripe requires a minimum charge amount of $0.50 USD
    if total_amount < 0.50
      raise ArgumentError, "Payment amount must be at least $0.50 USD. Current amount: $#{total_amount}"
    end
    
    amount_cents = (total_amount * 100).to_i
    platform_fee_cents = calculate_platform_fee_cents(amount_cents, business)

    # Prepare session parameters
    session_params = {
      payment_method_types: ['card'],
      line_items: [{
        price_data: {
          currency: 'usd',
          product_data: {
            name: "Invoice #{invoice.invoice_number}",
            description: "Payment for #{business.name}"
          },
          unit_amount: amount_cents
        },
        quantity: 1
      }],
      mode: 'payment',
      success_url: success_url,
      cancel_url: cancel_url,
      customer_creation: 'always', # Let Stripe create the customer during checkout
      customer_email: tenant_customer.email, # Pre-fill email
      payment_intent_data: {
        application_fee_amount: platform_fee_cents,
        metadata: { 
          business_id: business.id, 
          invoice_id: invoice.id,
          tenant_customer_id: tenant_customer.id
        }
      },
      metadata: { 
        business_id: business.id, 
        invoice_id: invoice.id,
        tenant_customer_id: tenant_customer.id
      }
    }
    
    # Ensure we have a valid Stripe customer for the tenant (on connected account)
    stripe_customer = ensure_stripe_customer_for_tenant(tenant_customer, business)
    if stripe_customer
      session_params[:customer] = stripe_customer.id
      session_params.delete(:customer_creation) # Don't create new customer if using existing
      session_params.delete(:customer_email) # Don't pre-fill if using existing customer
    end

    # Create the checkout session (direct charge on connected account)
    session = Stripe::Checkout::Session.create(session_params, {
      stripe_account: business.stripe_account_id
    })

    # Don't create payment record here - it will be created by the webhook
    # when the payment is actually processed by Stripe
    { session: session, payment: nil }
  end

  # Create a Stripe Checkout session for estimate deposit payment
  # This is called when a customer approves an estimate and needs to pay the deposit
  def self.create_estimate_deposit_checkout_session(estimate:, invoice:, payment_amount:, success_url:, cancel_url:)
    configure_stripe_api_key
    business = estimate.business
    tenant_customer = estimate.tenant_customer || invoice.tenant_customer

    # Stripe requires a minimum charge amount of $0.50 USD
    if payment_amount < 0.50
      raise ArgumentError, "Payment amount must be at least $0.50 USD. Current amount: $#{payment_amount}"
    end

    amount_cents = (payment_amount * 100).to_i
    platform_fee_cents = calculate_platform_fee_cents(amount_cents, business)

    # Build description for the payment
    description = "Estimate #{estimate.estimate_number || 'Draft'}"
    description += " - Deposit" if estimate.required_deposit.present? && estimate.required_deposit > 0

    # Prepare session parameters
    session_params = {
      payment_method_types: ['card'],
      line_items: [{
        price_data: {
          currency: 'usd',
          product_data: {
            name: description,
            description: "Payment for #{business.name}"
          },
          unit_amount: amount_cents
        },
        quantity: 1
      }],
      mode: 'payment',
      success_url: success_url,
      cancel_url: cancel_url,
      customer_creation: 'always',
      customer_email: estimate.customer_email,
      payment_intent_data: {
        application_fee_amount: platform_fee_cents,
        metadata: {
          business_id: business.id,
          estimate_id: estimate.id,
          invoice_id: invoice.id,
          tenant_customer_id: tenant_customer&.id,
          payment_type: 'estimate_deposit'
        }
      },
      metadata: {
        business_id: business.id,
        estimate_id: estimate.id,
        invoice_id: invoice.id,
        tenant_customer_id: tenant_customer&.id,
        payment_type: 'estimate_deposit'
      }
    }

    # Use existing Stripe customer if available
    if tenant_customer.present?
      stripe_customer = ensure_stripe_customer_for_tenant(tenant_customer, business)
      if stripe_customer
        session_params[:customer] = stripe_customer.id
        session_params.delete(:customer_creation)
        session_params.delete(:customer_email)
      end
    end

    # Create the checkout session (direct charge on connected account)
    session = Stripe::Checkout::Session.create(session_params, {
      stripe_account: business.stripe_account_id
    })

    { session: session }
  end

  # Create a Stripe Checkout session for rental security deposit
  def self.create_rental_deposit_checkout_session(rental_booking:, success_url:, cancel_url:)
    configure_stripe_api_key
    business = rental_booking.business
    tenant_customer = rental_booking.tenant_customer

    deposit_amount = rental_booking.security_deposit_amount.to_f

    # Stripe requires a minimum charge amount of $0.50 USD
    if deposit_amount < 0.50
      raise ArgumentError, "Deposit amount must be at least $0.50 USD. Current amount: $#{deposit_amount}"
    end

    # Validate connected account
    unless business.stripe_account_id.present?
      raise ArgumentError, "Business must have a Stripe Connect account to accept rental deposits"
    end

    # Ensure customer exists on the connected account
    stripe_customer = ensure_stripe_customer_for_tenant(tenant_customer, business)

    amount_cents = (deposit_amount * 100).to_i

    # Calculate platform fee (same logic as other payments)
    platform_fee = calculate_platform_fee_cents(amount_cents, business) / 100.0

    # Check if business uses preauthorization (hold funds) vs immediate capture (charge funds)
    use_preauth = business.rental_deposit_preauth_enabled?

    session_params = {
      payment_method_types: ['card'],
      mode: 'payment',
      customer: stripe_customer.id,
      line_items: [{
        price_data: {
          currency: 'usd',
          product_data: {
            name: "Security Deposit - #{rental_booking.rental_name}",
            description: "Refundable security deposit for rental booking ##{rental_booking.booking_number}"
          },
          unit_amount: amount_cents
        },
        quantity: 1
      }],
      metadata: {
        type: 'rental_deposit',
        rental_booking_id: rental_booking.id,
        business_id: business.id,
        customer_id: tenant_customer.id,
        booking_number: rental_booking.booking_number,
        preauth_enabled: use_preauth
      },
      payment_intent_data: {
        application_fee_amount: (platform_fee * 100).to_i,
        metadata: {
          type: 'rental_deposit',
          rental_booking_id: rental_booking.id,
          booking_number: rental_booking.booking_number
        }
      },
      success_url: success_url,
      cancel_url: cancel_url
    }

    # Add manual capture mode if preauth is enabled
    if use_preauth
      session_params[:payment_intent_data][:capture_method] = 'manual'
      Rails.logger.info "[RENTAL_DEPOSIT] Creating preauthorization checkout session for booking #{rental_booking.booking_number}"
    else
      Rails.logger.info "[RENTAL_DEPOSIT] Creating immediate capture checkout session for booking #{rental_booking.booking_number}"
    end

    # Create the checkout session on the connected account
    session = Stripe::Checkout::Session.create(session_params, {
      stripe_account: business.stripe_account_id
    })

    session
  end

  def self.create_client_document_checkout_session(document:, success_url:, cancel_url:)
    configure_stripe_api_key
    business = document.business
    tenant_customer = document.tenant_customer

    unless business.stripe_account_id.present?
      raise ArgumentError, "Business must have a Stripe Connect account to collect document deposits"
    end

    deposit_amount = document.deposit_amount.to_f
    raise ArgumentError, "Payment amount must be at least $0.50 USD. Current amount: $#{deposit_amount}" if deposit_amount < 0.50

    stripe_customer = tenant_customer.present? ? ensure_stripe_customer_for_tenant(tenant_customer, business) : nil
    amount_cents = (deposit_amount * 100).to_i
    platform_fee_cents = calculate_platform_fee_cents(amount_cents, business)

    metadata = {
      payment_type: 'client_document',
      client_document_id: document.id,
      business_id: business.id,
      documentable_type: document.documentable_type,
      documentable_id: document.documentable_id,
      invoice_id: document.invoice_id
    }.compact

    session_params = {
      payment_method_types: ['card'],
      line_items: [{
        price_data: {
          currency: document.currency || 'usd',
          product_data: {
            name: document.title.presence || document.document_type.titleize,
            description: "Payment for #{business.name}"
          },
          unit_amount: amount_cents
        },
        quantity: 1
      }],
      mode: 'payment',
      success_url: success_url,
      cancel_url: cancel_url,
      metadata: metadata,
      payment_intent_data: {
        application_fee_amount: platform_fee_cents,
        metadata: metadata
      }
    }

    if stripe_customer
      session_params[:customer] = stripe_customer.id
    elsif tenant_customer&.email.present?
      session_params[:customer_creation] = 'always'
      session_params[:customer_email] = tenant_customer.email
    end

    session = Stripe::Checkout::Session.create(session_params, {
      stripe_account: business.stripe_account_id
    })

    { session: session }
  end

  # Capture a preauthorized rental deposit (charge the held funds)
  # @param rental_booking [RentalBooking] The rental booking with authorized deposit
  # @return [Hash] Result hash with :success and :error keys
  def self.capture_rental_deposit_authorization(rental_booking)
    configure_stripe_api_key
    business = rental_booking.business

    unless rental_booking.deposit_authorization_id.present?
      return { success: false, error: 'No authorization ID found for this rental booking' }
    end

    if rental_booking.deposit_captured_at.present?
      return { success: false, error: 'Deposit has already been captured' }
    end

    begin
      # Capture the authorized payment intent
      payment_intent = Stripe::PaymentIntent.capture(
        rental_booking.deposit_authorization_id,
        { stripe_account: business.stripe_account_id }
      )

      Rails.logger.info "[RENTAL_DEPOSIT] Successfully captured preauthorization #{rental_booking.deposit_authorization_id} for booking #{rental_booking.booking_number}"

      { success: true, payment_intent: payment_intent }
    rescue Stripe::InvalidRequestError => e
      Rails.logger.error "[RENTAL_DEPOSIT] Invalid request when capturing authorization for booking #{rental_booking.booking_number}: #{e.message}"
      { success: false, error: e.message }
    rescue Stripe::StripeError => e
      Rails.logger.error "[RENTAL_DEPOSIT] Stripe error capturing authorization for booking #{rental_booking.booking_number}: #{e.message}"
      { success: false, error: e.message }
    rescue => e
      Rails.logger.error "[RENTAL_DEPOSIT] Unexpected error capturing authorization for booking #{rental_booking.booking_number}: #{e.message}"
      { success: false, error: e.message }
    end
  end

  # Cancel a preauthorized rental deposit (release the hold without charging)
  # @param rental_booking [RentalBooking] The rental booking with authorized deposit
  # @return [Hash] Result hash with :success and :error keys
  def self.cancel_rental_deposit_authorization(rental_booking)
    configure_stripe_api_key
    business = rental_booking.business

    unless rental_booking.deposit_authorization_id.present?
      return { success: false, error: 'No authorization ID found for this rental booking' }
    end

    if rental_booking.deposit_captured_at.present?
      return { success: false, error: 'Cannot cancel - deposit has already been captured' }
    end

    if rental_booking.deposit_authorization_released_at.present?
      return { success: false, error: 'Authorization has already been released' }
    end

    begin
      # Cancel the authorized payment intent
      payment_intent = Stripe::PaymentIntent.cancel(
        rental_booking.deposit_authorization_id,
        { stripe_account: business.stripe_account_id }
      )

      Rails.logger.info "[RENTAL_DEPOSIT] Successfully cancelled preauthorization #{rental_booking.deposit_authorization_id} for booking #{rental_booking.booking_number}"

      { success: true, payment_intent: payment_intent }
    rescue Stripe::InvalidRequestError => e
      Rails.logger.error "[RENTAL_DEPOSIT] Invalid request when cancelling authorization for booking #{rental_booking.booking_number}: #{e.message}"
      { success: false, error: e.message }
    rescue Stripe::StripeError => e
      Rails.logger.error "[RENTAL_DEPOSIT] Stripe error cancelling authorization for booking #{rental_booking.booking_number}: #{e.message}"
      { success: false, error: e.message }
    rescue => e
      Rails.logger.error "[RENTAL_DEPOSIT] Unexpected error cancelling authorization for booking #{rental_booking.booking_number}: #{e.message}"
      { success: false, error: e.message }
    end
  end

  # Process rental deposit refund
  def self.process_rental_deposit_refund(rental_booking:, refund_amount:)
    configure_stripe_api_key
    business = rental_booking.business

    return unless rental_booking.stripe_deposit_payment_intent_id.present?
    return unless refund_amount.to_d > 0

    refund_amount_cents = (refund_amount.to_d * 100).to_i
    
    begin
      refund = Stripe::Refund.create(
        {
          payment_intent: rental_booking.stripe_deposit_payment_intent_id,
          amount: refund_amount_cents,
          metadata: {
            type: 'rental_deposit_refund',
            rental_booking_id: rental_booking.id,
            booking_number: rental_booking.booking_number
          }
        },
        { stripe_account: business.stripe_account_id }
      )
      
      Rails.logger.info("[StripeService] Refund processed for rental #{rental_booking.booking_number}: #{refund.id}")
      refund
    rescue Stripe::StripeError => e
      Rails.logger.error("[StripeService] Failed to process refund for rental #{rental_booking.booking_number}: #{e.message}")
      raise
    end
  end

  # Create a Stripe Checkout session for tip payment
  def self.create_tip_checkout_session(tip:, success_url:, cancel_url:)
    configure_stripe_api_key
    business = tip.business
    tenant_customer = tip.tenant_customer

    tip_amount = tip.amount.to_f
    
    # Stripe requires a minimum charge amount of $0.50 USD
    if tip_amount < 0.50
      raise ArgumentError, "Tip amount must be at least $0.50 USD. Current amount: $#{tip_amount}"
    end
    
    amount_cents = (tip_amount * 100).to_i
    # Calculate platform fee for tips based on business tier
    platform_fee_cents = calculate_platform_fee_cents(amount_cents, business)

    # Prepare session parameters
    session_params = {
      payment_method_types: ['card'],
      line_items: [{
        price_data: {
          currency: 'usd',
          product_data: {
            name: "Tip for #{business.name}",
            description: "Thank you for your experience with #{business.name}"
          },
          unit_amount: amount_cents
        },
        quantity: 1
      }],
      mode: 'payment',
      success_url: success_url,
      cancel_url: cancel_url,
      customer_creation: 'always', # Let Stripe create the customer during checkout
      customer_email: tenant_customer.email, # Pre-fill email
      payment_intent_data: {
        application_fee_amount: platform_fee_cents,
        metadata: { 
          business_id: business.id, 
          tip_id: tip.id,
          tenant_customer_id: tenant_customer.id,
          payment_type: 'tip'
        }
      },
      metadata: { 
        business_id: business.id, 
        tip_id: tip.id,
        tenant_customer_id: tenant_customer.id,
        payment_type: 'tip'
      }
    }
    
    # Ensure we have a valid Stripe customer for the tenant (on connected account)
    stripe_customer = ensure_stripe_customer_for_tenant(tenant_customer, business)
    if stripe_customer
      session_params[:customer] = stripe_customer.id
      session_params.delete(:customer_creation) # Don't create new customer if using existing
      session_params.delete(:customer_email) # Don't pre-fill if using existing customer
    end

    # Create the checkout session for tip (direct charge on connected account)
    session = Stripe::Checkout::Session.create(session_params, {
      stripe_account: business.stripe_account_id
    })

    # Don't create payment record here - it will be created by the webhook
    # when the payment is actually processed by Stripe
    { session: session, tip: tip }
  end

  # Create a Stripe Payment Link with integrated tipping
  def self.create_payment_link_with_tipping(invoice:, success_url:)
    configure_stripe_api_key
    business = invoice.business
    tenant_customer = invoice.tenant_customer

    total_amount = invoice.total_amount.to_f
    
    # Stripe requires a minimum charge amount of $0.50 USD
    if total_amount < 0.50
      raise ArgumentError, "Payment amount must be at least $0.50 USD. Current amount: $#{total_amount}"
    end
    
    amount_cents = (total_amount * 100).to_i
    platform_fee_cents = calculate_platform_fee_cents(amount_cents, business)

    # Get tip configuration for the business
    tip_config = business.tip_configuration_or_default
    tip_percentages = tip_config.tip_percentage_options

    # Create Payment Link with integrated tipping
    payment_link = Stripe::PaymentLink.create({
      line_items: [{
        price_data: {
          currency: 'usd',
          product_data: {
            name: "Service Fee",
            description: "Payment for #{business.name}"
          },
          unit_amount: amount_cents
        },
        quantity: 1
      }],
      transfer_data: {
        destination: business.stripe_account_id,
      },
      application_fee_amount: platform_fee_cents,
      after_completion: { type: 'redirect', redirect: { url: success_url } },
      # Enable tipping with business-configured percentages
      custom_text: { 
        submit: { 
          message: tip_config.tip_message.present? ? tip_config.tip_message : "Add a tip for excellent service!" 
        } 
      },
      tipping: {
        amount_calculations: tip_percentages.map { |percent| { percent: percent } },
        # Include tips in application fee calculation
        application_fee_behavior: 'calculate_from_total'
      },
      # Note: Stripe doesn't currently support combining preset tip percentages with custom tip amounts
      # in the same payment link. Custom amounts would require using custom_unit_amount instead of tipping.
      metadata: {
        business_id: business.id,
        invoice_id: invoice.id,
        tenant_customer_id: tenant_customer.id,
        payment_type: 'invoice_with_tipping'
      }
    })

    { payment_link: payment_link, invoice: invoice }
  rescue Stripe::StripeError => e
    Rails.logger.error "[STRIPE] Failed to create payment link with tipping for invoice #{invoice.id}: #{e.message}"
    raise
  end

  # Create a payment intent for an invoice or order
  def self.create_payment_intent(invoice:, order: nil, payment_method_id: nil)
    configure_stripe_api_key
    business = invoice.business
    tenant_customer = invoice.tenant_customer

    total_amount = invoice.total_amount.to_f
    
    # Stripe requires a minimum charge amount of $0.50 USD
    if total_amount < 0.50
      raise ArgumentError, "Payment amount must be at least $0.50 USD. Current amount: $#{total_amount}"
    end
    
    amount_cents = (total_amount * 100).to_i
    stripe_fee_cents = calculate_stripe_fee_cents(amount_cents)
    platform_fee_cents = calculate_platform_fee_cents(amount_cents, business)

    # Prepare payment intent parameters
    intent_params = {
      amount: amount_cents,
      currency: 'usd',
      payment_method: payment_method_id,
      confirm: payment_method_id.present?,
      metadata: { business_id: business.id, invoice_id: invoice.id, order_id: order&.id },
      application_fee_amount: platform_fee_cents
    }
    
    # Ensure we have a valid Stripe customer for the tenant (on connected account)
    stripe_customer = ensure_stripe_customer_for_tenant(tenant_customer, business)
    customer_id = nil
    if stripe_customer
      intent_params[:customer] = stripe_customer.id
      customer_id = stripe_customer.id
    end

    intent = Stripe::PaymentIntent.create(intent_params, {
      stripe_account: business.stripe_account_id
    })

    # Calculate fee values for record
    stripe_fee_amount   = stripe_fee_cents / 100.0
    platform_fee_amount = platform_fee_cents / 100.0
    business_amount     = (total_amount - stripe_fee_amount - platform_fee_amount).round(2)

    payment = Payment.create!(
      business: business,
      invoice: invoice,
      order: order,
      tenant_customer: tenant_customer,
      amount: total_amount,
      stripe_fee_amount:   stripe_fee_amount,
      platform_fee_amount: platform_fee_amount,
      business_amount:     business_amount,
      stripe_payment_intent_id: intent.id,
      stripe_customer_id: customer_id, # Will be nil if no customer
      payment_method: payment_method_id.present? ? :credit_card : :other,
      status: :pending
    )

    { id: intent.id, client_secret: intent.client_secret, payment: payment }
  end

  # Process raw webhook payload (as JSON string)
  def self.process_webhook(event_json, tenant_context = nil)
    configure_stripe_api_key
    event = JSON.parse(event_json)
    
    Rails.logger.info "[STRIPE_SERVICE] Processing webhook #{event['type']} with tenant context: #{tenant_context&.name || 'None'}"
    
    case event['type']
    when 'payment_intent.succeeded'
      handle_successful_payment(event['data']['object'], tenant_context)
    when 'payment_intent.payment_failed'
      handle_failed_payment(event['data']['object'], tenant_context)
    when 'charge.refunded'
      handle_refund(event['data']['object'], tenant_context)
    when 'account.updated'
      handle_account_updated(event['data']['object'])
    when 'checkout.session.completed'
      handle_checkout_session_completed(event['data']['object'])
    when 'customer.subscription.deleted', 'customer.subscription.updated', 'customer.subscription.created'
      handle_subscription_event(event['data']['object'])
    when 'invoice.payment_succeeded'
      handle_customer_subscription_payment_succeeded(event['data']['object'])
    when 'invoice.payment_failed'
      handle_customer_subscription_payment_failed(event['data']['object'])
    
    else
      Rails.logger.info "Unhandled Stripe event: #{event['type']}"
    end
  rescue JSON::ParserError => e
    Rails.logger.error "StripeService invalid JSON: #{e.message}"
  end

  # Create a refund in Stripe and update payment record
  def self.create_refund(payment, amount: nil, reason: nil)
    configure_stripe_api_key
    params = { payment_intent: payment.stripe_payment_intent_id }
    params[:amount] = (amount * 100).to_i if amount
    params[:metadata] = { reason: reason } if reason
    refund = Stripe::Refund.create(params, {
      stripe_account: payment.business.stripe_account_id
    })

    refunded_amt = refund.amount_refunded / 100.0
    payment.update!(status: :refunded, refunded_amount: refunded_amt, refund_reason: reason)

    # Cascade updates to related records
    if (invoice = payment.invoice)
      # If all payments on this invoice are refunded, mark invoice as cancelled
      if invoice.payments.where.not(status: :refunded).none?
        invoice.update!(status: :cancelled)
        # Update order status if applicable - use helper method to ensure consistency
        if (order = invoice.order)
          order.check_and_update_refund_status!
        end
      end
    end
    refund
  end

  # Helper to map business tier to Stripe price ID
  def self.get_stripe_price_id(tier)
    case tier.to_s.downcase
    when 'standard'
      ENV['STRIPE_STANDARD_PRICE_ID']
    when 'premium'
      ENV['STRIPE_PREMIUM_PRICE_ID']
    end
  end

  def self.create_tip_payment_session(tip:, success_url:, cancel_url:)
    configure_stripe_api_key
    business = tip.business
    
    # Ensure business has Stripe Connect account
    unless business.stripe_account_id.present?
      raise ArgumentError, "Business must have a connected Stripe account to process tips"
    end
    
    # Calculate amount in cents
    amount_cents = (tip.amount * 100).to_i
    platform_fee_cents = calculate_platform_fee_cents(amount_cents, business)
    
    # Minimum amount check
    if amount_cents < 50 # $0.50 minimum
      raise ArgumentError, "Tip amount must be at least $0.50"
    end
    
    begin
      session = Stripe::Checkout::Session.create({
        payment_method_types: ['card'],
        line_items: [{
          price_data: {
            currency: 'usd',
            product_data: {
              name: "Tip for #{business.name}",
              description: "Thank you for showing your appreciation!"
            },
            unit_amount: amount_cents
          },
          quantity: 1
        }],
        mode: 'payment',
        success_url: success_url,
        cancel_url: cancel_url,
        client_reference_id: tip.id.to_s,
        payment_intent_data: {
          application_fee_amount: platform_fee_cents,
          metadata: {
            tip_id: tip.id.to_s,
            booking_id: tip.booking&.id.to_s,
            business_id: business.id.to_s,
            tip_context: "Tip for #{tip.booking&.service&.name || 'service'}"
          }
        },
        metadata: {
          tip_id: tip.id.to_s,
          booking_id: tip.booking&.id.to_s,
          business_id: business.id.to_s,
          tip_context: "Tip for #{tip.booking&.service&.name || 'service'}"
        }
      }, {
        stripe_account: business.stripe_account_id
      })
      
      Rails.logger.info "Created Stripe tip session #{session.id} for tip #{tip.id}"
      
      { success: true, session: session }
    rescue Stripe::StripeError => e
      Rails.logger.error "Stripe error creating tip session: #{e.message}"
      raise e
    end
  end

  # Create a Stripe Checkout session for customer subscription signup
  def self.create_subscription_checkout_session(subscription_data:, success_url:, cancel_url:)
    # In development mode without Stripe keys, return a mock response immediately
    if Rails.env.development? && !stripe_configured?
      Rails.logger.info "[STRIPE] Development mode - mocking subscription checkout session"
      return { 
        success: false, 
        error: "Stripe not configured for development. In production, this would redirect to Stripe Checkout." 
      }
    end
    
    configure_stripe_api_key
    
    business = Business.find(subscription_data[:business_id])
    tenant_customer = TenantCustomer.find(subscription_data[:tenant_customer_id])
    
    # In development mode, if business doesn't have Stripe Connect account, return mock response
    if Rails.env.development? && !business.stripe_account_id.present?
      Rails.logger.info "[STRIPE] Development mode - business has no Stripe Connect account, mocking subscription checkout session"
      return { 
        success: false, 
        error: "Stripe Connect not configured for this business in development. In production, this would redirect to Stripe Checkout." 
      }
    end
    
    # Ensure business has Stripe Connect account
    unless business.stripe_account_id.present?
      raise ArgumentError, "Business must have a connected Stripe account to process subscriptions"
    end
    
    # Calculate subscription amount
    subscription_price = subscription_data[:subscription_price].to_f
    amount_cents = (subscription_price * 100).to_i
    
    # Minimum amount check
    if amount_cents < 50 # $0.50 minimum
      raise ArgumentError, "Subscription amount must be at least $0.50"
    end
    
    begin
      # Prepare customer data for Stripe Checkout (don't create customer yet)
      customer_data = {
        email: tenant_customer.email,
        name: tenant_customer.full_name
      }
      
      # Add phone if available
      customer_data[:phone] = tenant_customer.phone if tenant_customer.phone.present?
      
      session_params = {
        payment_method_types: ['card'],
        mode: 'subscription',
        line_items: [{
          price_data: {
            currency: 'usd',
            product_data: {
              name: subscription_data[:item_name],
              description: "#{subscription_data[:frequency].humanize} subscription"
            },
            unit_amount: amount_cents,
            recurring: {
              interval: 'month',
              interval_count: 1
            }
          },
          quantity: subscription_data[:quantity] || 1
        }],
        success_url: success_url,
        cancel_url: cancel_url,
        customer_creation: 'always', # Let Stripe create the customer during checkout
        customer_email: tenant_customer.email, # Pre-fill email
        metadata: {
          business_id: business.id.to_s,
          tenant_customer_id: tenant_customer.id.to_s,
          subscription_type: subscription_data[:subscription_type],
          item_id: subscription_data[:item_id].to_s,
          subscription_data: subscription_data.to_json
        }
      }
      
      # Only set existing customer if we already have a Stripe customer ID
      if tenant_customer.stripe_customer_id.present?
        begin
          # Verify the customer exists in Stripe before using it
          Stripe::Customer.retrieve(tenant_customer.stripe_customer_id, { stripe_account: business.stripe_account_id })
          session_params[:customer] = tenant_customer.stripe_customer_id
          session_params.delete(:customer_creation) # Don't create new customer if using existing
          session_params.delete(:customer_email) # Don't pre-fill if using existing customer
        rescue Stripe::InvalidRequestError => e
          # Customer doesn't exist in Stripe, clear the ID and let Stripe create a new one
          Rails.logger.warn "Stripe customer #{tenant_customer.stripe_customer_id} not found, letting Stripe create new customer for tenant #{tenant_customer.id}"
          tenant_customer.update!(stripe_customer_id: nil)
        end
      end
      
      session = Stripe::Checkout::Session.create(session_params, {
        stripe_account: business.stripe_account_id
      })
      
      Rails.logger.info "Created Stripe subscription session #{session.id} for customer #{tenant_customer.id}"
      
      { success: true, session: session }
    rescue Stripe::StripeError => e
      Rails.logger.error "Stripe error creating subscription session: #{e.message}"
      
      # In development mode, return a friendly mock response instead of raising the error
      if Rails.env.development?
        Rails.logger.info "[STRIPE] Development mode - Stripe API error caught, returning mock response"
        return { 
          success: false, 
          error: "Stripe Connect account not properly configured in development. In production, this would redirect to Stripe Checkout." 
        }
      end
      
      raise e
    end
  end

  private

  # Calculate Stripe's fee in cents (2.9% + 30¢)
  def self.calculate_stripe_fee_cents(amount_cents)
    (amount_cents * 0.029).round + 30
  end

  # Calculate platform fee in cents based on business tier
  def self.calculate_platform_fee_cents(amount_cents, business)
    rate = case business.tier
           when 'premium' then 0.03
           else 0.05
           end
    (amount_cents * rate).round
  end

  # Retrieve or create Stripe Customer for tenant
  def self.ensure_stripe_customer_for_tenant(tenant, business)
    # In development or test mode without Stripe keys, return a mock customer
    if (Rails.env.development? || Rails.env.test?) && !stripe_configured?
      Rails.logger.info "[STRIPE] #{Rails.env} mode - mocking customer creation for tenant #{tenant.id}"
      return OpenStruct.new(id: "cus_#{Rails.env}_#{tenant.id}", email: tenant.email)
    end
    
    # Determine connected account context (explicit business or current tenant)
    connected_account_id = business&.stripe_account_id || ActsAsTenant.current_tenant&.stripe_account_id
    stripe_account_options = connected_account_id.present? ? { stripe_account: connected_account_id } : {}
    
    if tenant.stripe_customer_id.present?
      begin
        return Stripe::Customer.retrieve(tenant.stripe_customer_id, stripe_account_options)
      rescue Stripe::InvalidRequestError => e
        # Customer doesn't exist in Stripe, clear the ID and create a new one
        Rails.logger.warn "Stripe customer #{tenant.stripe_customer_id} not found, creating new customer for tenant #{tenant.id}"
        tenant.update!(stripe_customer_id: nil)
      end
    end
    
    # Create new Stripe customer (on connected account if business provided)
    customer = Stripe::Customer.create(
      {
        email: tenant.email, 
        name: tenant.full_name, 
        metadata: { tenant_customer_id: tenant.id }
      },
      stripe_account_options
    )
    tenant.update!(stripe_customer_id: customer.id)
    customer
  end

  # Retrieve or create Stripe Customer for business (for subscription billing)
  def self.ensure_stripe_customer_for_business(business)
    # In development or test mode without Stripe keys, return a mock customer
    if (Rails.env.development? || Rails.env.test?) && !stripe_configured?
      Rails.logger.info "[STRIPE] #{Rails.env} mode - mocking customer creation for business #{business.id}"
      return OpenStruct.new(id: "cus_#{Rails.env}_business_#{business.id}", email: business.email)
    end
    
    if business.stripe_customer_id.present?
      begin
        return Stripe::Customer.retrieve(business.stripe_customer_id)
      rescue Stripe::InvalidRequestError => e
        # Customer doesn't exist in Stripe, clear the ID and create a new one
        Rails.logger.warn "Stripe customer #{business.stripe_customer_id} not found, creating new customer for business #{business.id}"
        business.update!(stripe_customer_id: nil)
      end
    end
    
    customer = Stripe::Customer.create(email: business.email, name: business.name, metadata: { business_id: business.id })
    business.update!(stripe_customer_id: customer.id)
    customer
  end

  # Handle successful checkout session completion for payments and registrations
  def self.handle_checkout_session_completed(session)
    # Check if this is a business registration
    if session.dig('metadata', 'payment_type') == 'client_document' && session.dig('metadata', 'client_document_id').present?
      handle_client_document_payment_completion(session)
      return
    end

    if session.dig('metadata', 'registration_type') == 'business'
      handle_business_registration_completion(session)
      return
    end

    # Check if this is a subscription signup
    if session['mode'] == 'subscription' && session.dig('metadata', 'subscription_type').present?
      handle_subscription_signup_completion(session)
      return
    end

    # Check if this is a booking payment
    if session.dig('metadata', 'booking_type') == 'service_booking'
      handle_booking_payment_completion(session)
      return
    end

    # Check if this is a tip payment
    if session.dig('metadata', 'payment_type') == 'tip'
      handle_tip_payment_completion(session)
      return
    end

    # Check if this is an estimate deposit payment
    if session.dig('metadata', 'payment_type') == 'estimate_deposit'
      handle_estimate_payment_completion(session)
      return
    end

    # Check if this is a rental security deposit payment
    if session.dig('metadata', 'type') == 'rental_deposit'
      handle_rental_deposit_payment_completion(session)
      return
    end

    # Check if this is a payment (not subscription) by looking for invoice_id in metadata
    invoice_id = session.dig('metadata', 'invoice_id')
    return unless invoice_id

    # Find the invoice and related records
    invoice = Invoice.find_by(id: invoice_id)
    return unless invoice

    business = invoice.business
    tenant_customer = invoice.tenant_customer
    
    # Save the Stripe customer ID if we don't have it yet
    if session['customer'].present? && tenant_customer.stripe_customer_id.blank?
      tenant_customer.update!(stripe_customer_id: session['customer'])
      Rails.logger.info "[PAYMENT] Saved Stripe customer ID #{session['customer']} for tenant customer #{tenant_customer.id}"
    end
    
    # Check if payment record already exists
    payment = Payment.find_by(stripe_payment_intent_id: session['payment_intent'])
    
    if payment.nil?
      # Create the payment record now that we have the payment_intent_id
      total_amount = invoice.total_amount.to_f
      amount_cents = (total_amount * 100).to_i
      
      stripe_fee_amount   = calculate_stripe_fee_cents(amount_cents) / 100.0
      platform_fee_amount = calculate_platform_fee_cents(amount_cents, business) / 100.0
      business_amount     = (total_amount - stripe_fee_amount - platform_fee_amount).round(2)

      payment = Payment.create!(
        business: business,
        invoice: invoice,
        order: invoice.order,
        tenant_customer: tenant_customer,
        amount: total_amount,
        stripe_fee_amount:   stripe_fee_amount,
        platform_fee_amount: platform_fee_amount,
        business_amount:     business_amount,
        stripe_payment_intent_id: session['payment_intent'],
        stripe_customer_id: session['customer'],
        payment_method: :credit_card,
        status: :completed,
        paid_at: Time.current
      )
    else
      # Update existing payment record
      payment.update!(status: :completed, paid_at: Time.current, payment_method: :credit_card)
    end

    # Mark invoice as paid
    invoice.mark_as_paid! if invoice.pending?
    
    # Update order status if applicable
    if (order = payment.order)
      new_status = order.payment_required? ? :paid : :processing
      order.update!(status: new_status)
      
      # Check if order should be completed (for service orders without bookings)
      order.complete_if_ready!
      
      # Send order confirmation (email + SMS)
      begin
        NotificationService.order_confirmation(order)
        Rails.logger.info "[NOTIFICATION] Sent order confirmation for Order ##{order.order_number}"
      rescue => e
        Rails.logger.error "[NOTIFICATION] Failed to send order confirmation for Order ##{order.order_number}: #{e.message}"
      end
      
      # Send business payment notification (email + SMS)
      begin
        NotificationService.business_payment_received(payment)
        Rails.logger.info "[NOTIFICATION] Scheduled business payment notification for Order ##{order.order_number}"
      rescue => e
        Rails.logger.error "[NOTIFICATION] Failed to schedule business payment notification for Order ##{order.order_number}: #{e.message}"
      end
    else
      # Send invoice payment confirmation (email + SMS)
      begin
        NotificationService.invoice_payment_confirmation(invoice, payment)
        Rails.logger.info "[NOTIFICATION] Sent payment confirmation for Invoice ##{invoice.invoice_number}"
      rescue => e
        Rails.logger.error "[NOTIFICATION] Failed to send payment confirmation for Invoice ##{invoice.invoice_number}: #{e.message}"
      end
      
      # Send business payment notification (email + SMS)
      begin
        NotificationService.business_payment_received(payment)
        Rails.logger.info "[NOTIFICATION] Scheduled business payment notification for Invoice ##{invoice.invoice_number}"
      rescue => e
        Rails.logger.error "[NOTIFICATION] Failed to schedule business payment notification for Invoice ##{invoice.invoice_number}: #{e.message}"
      end
    end
  end

  def self.handle_successful_payment(pi, tenant_context = nil)
    # Try to find payment with tenant context first
    payment = if tenant_context
      Rails.logger.info "[PAYMENT] Looking for payment in tenant context: #{tenant_context.name}"
      ActsAsTenant.with_tenant(tenant_context) do
        Payment.find_by(stripe_payment_intent_id: pi['id'])
      end
    else
      # Fallback to unscoped search across all tenants
      Rails.logger.info "[PAYMENT] Looking for payment across all tenants"
      Payment.unscoped.find_by(stripe_payment_intent_id: pi['id'])
    end
    
    return unless payment
    
    # Ensure we're in the correct tenant context for the payment
    ActsAsTenant.with_tenant(payment.business) do
      Rails.logger.info "[PAYMENT] Processing successful payment #{payment.id} for business #{payment.business.name}"
      
      # Determine payment method from Stripe data
      payment_method = case pi.dig('charges', 'data', 0, 'payment_method_details', 'type')
                      when 'card' then :credit_card
                      when 'us_bank_account' then :bank_transfer
                      when 'paypal' then :paypal
                      else :other
                      end
      
      # Check for tip amount from payment link tipping
      tip_amount = extract_tip_amount_from_payment_intent(pi)
      
      # Update payment with tip tracking if tip was received
      if tip_amount > 0
        payment.update!(
          status: :completed, 
          paid_at: Time.current, 
          payment_method: payment_method,
          tip_received_on_initial_payment: true,
          tip_amount_received_initially: tip_amount
        )
        
        # Also update the invoice and order with tip tracking
        if payment.invoice
          payment.invoice.update!(
            tip_received_on_initial_payment: true,
            tip_amount_received_initially: tip_amount
          )
        end
        
        if payment.order
          payment.order.update!(
            tip_received_on_initial_payment: true,
            tip_amount_received_initially: tip_amount
          )
        end
        
        Rails.logger.info "[PAYMENT] Tip of $#{tip_amount} received with payment #{payment.id}"
      else
        payment.update!(status: :completed, paid_at: Time.current, payment_method: payment_method)
      end
      
      payment.invoice.mark_as_paid! if payment.invoice&.pending?
      
      # Update order status if applicable
      if (order = payment.order)
        # For product or experience orders, mark as paid; for services, mark as processing
        new_status = order.payment_required? ? :paid : :processing
        order.update!(status: new_status)
        
        # Check if order should be completed (for service orders without bookings)
        order.complete_if_ready!
      else
        # No associated order – this is a standalone invoice payment. Send confirmation (email + SMS).
        begin
          NotificationService.invoice_payment_confirmation(payment.invoice, payment)
          Rails.logger.info "[NOTIFICATION] Sent payment confirmation for Invoice ##{payment.invoice.invoice_number}"
        rescue => e
          Rails.logger.error "[NOTIFICATION] Failed to send payment confirmation for Invoice ##{payment.invoice&.invoice_number}: #{e.message}"
        end
      end
    end
  end

  def self.handle_failed_payment(pi, tenant_context = nil)
    # Try to find payment with tenant context first
    payment = if tenant_context
      Rails.logger.info "[PAYMENT] Looking for failed payment in tenant context: #{tenant_context.name}"
      ActsAsTenant.with_tenant(tenant_context) do
        Payment.find_by(stripe_payment_intent_id: pi['id'])
      end
    else
      # Fallback to unscoped search across all tenants
      Rails.logger.info "[PAYMENT] Looking for failed payment across all tenants"
      Payment.unscoped.find_by(stripe_payment_intent_id: pi['id'])
    end
    
    return unless payment
    
    # Ensure we're in the correct tenant context for the payment
    ActsAsTenant.with_tenant(payment.business) do
      Rails.logger.info "[PAYMENT] Processing failed payment #{payment.id} for business #{payment.business.name}"
      payment.update!(status: :failed, failure_reason: pi['last_payment_error']&.dig('message'))
    end
  end

  def self.handle_refund(charge, tenant_context = nil)
    # Try to find payment with tenant context first
    payment = if tenant_context
      Rails.logger.info "[REFUND] Looking for refund payment in tenant context: #{tenant_context.name}"
      ActsAsTenant.with_tenant(tenant_context) do
        Payment.find_by(stripe_charge_id: charge['id'])
      end
    else
      # Fallback to unscoped search across all tenants
      Rails.logger.info "[REFUND] Looking for refund payment across all tenants"
      Payment.unscoped.find_by(stripe_charge_id: charge['id'])
    end
    
    return unless payment
    
    # Ensure we're in the correct tenant context for the payment
    ActsAsTenant.with_tenant(payment.business) do
      Rails.logger.info "[REFUND] Processing refund for payment #{payment.id} for business #{payment.business.name}"
      refunded_amt = charge['amount_refunded'] / 100.0
      reason = charge['refunds']&.dig('data')&.first&.dig('reason')
      payment.update!(status: :refunded, refunded_amount: refunded_amt, refund_reason: reason)

      # Cascade updates to related records
      if (invoice = payment.invoice)
        # If all payments on this invoice are refunded, mark invoice as cancelled
        if invoice.payments.where.not(status: :refunded).none?
          invoice.update!(status: :cancelled)
          # Update order status if applicable - use helper method to ensure consistency
          if (order = invoice.order)
            order.check_and_update_refund_status!
          end
        end
      end
    end
  end

  def self.handle_subscription_event(sub)
    # Check if this is a business platform subscription (has business metadata)
    if sub.dig('metadata', 'business_id') || Business.exists?(stripe_customer_id: sub['customer'])
      # Handle business platform subscription
      if sub['status'] == 'canceled'
        handle_subscription_suspension(sub)
      else
        record = Subscription.find_by(stripe_subscription_id: sub['id'])
        return unless record
        record.update!(status: sub['status'], current_period_end: Time.at(sub['current_period_end']).to_datetime)
      end
    else
      # Handle customer subscription
      handle_customer_subscription_event(sub)
    end
  end

  # Handle customer subscription events (product/service subscriptions)
  def self.handle_customer_subscription_event(stripe_subscription)
    Rails.logger.info "[CUSTOMER_SUB] Processing customer subscription event: #{stripe_subscription['id']} - #{stripe_subscription['status']}"
    
    # Find subscription across all tenants since webhooks don't have tenant context
    customer_subscription = CustomerSubscription.unscoped.find_by(stripe_subscription_id: stripe_subscription['id'])
    return unless customer_subscription
    
    # Set tenant context for the subscription's business
    ActsAsTenant.with_tenant(customer_subscription.business) do
      case stripe_subscription['status']
      when 'active'
        customer_subscription.update!(status: :active)
        Rails.logger.info "[CUSTOMER_SUB] Activated subscription #{customer_subscription.id}"
      when 'canceled'
        customer_subscription.update!(status: :cancelled)
        Rails.logger.info "[CUSTOMER_SUB] Cancelled subscription #{customer_subscription.id}"
      when 'incomplete_expired'
        customer_subscription.update!(status: :failed)
        Rails.logger.info "[CUSTOMER_SUB] Failed subscription #{customer_subscription.id}"
      when 'past_due'
        customer_subscription.update!(status: :failed)
        Rails.logger.info "[CUSTOMER_SUB] Failed subscription #{customer_subscription.id}"
      else
        Rails.logger.warn "[CUSTOMER_SUB] Unknown Stripe status: #{stripe_subscription['status']} for subscription #{customer_subscription.id}"
      end
    end
  rescue => e
    Rails.logger.error "[CUSTOMER_SUB] Error handling subscription event for #{stripe_subscription['id']}: #{e.message}"
  end

  # Handle successful subscription payment
  def self.handle_customer_subscription_payment_succeeded(stripe_invoice)
    Rails.logger.info "[CUSTOMER_SUB] Processing successful payment for invoice: #{stripe_invoice['id']}"
    
    # Find the subscription from the invoice
    stripe_subscription_id = stripe_invoice['subscription']
    return unless stripe_subscription_id
    
    # Find subscription across all tenants since webhooks don't have tenant context
    customer_subscription = CustomerSubscription.unscoped.find_by(stripe_subscription_id: stripe_subscription_id)
    return unless customer_subscription
    
    # Set tenant context for the subscription's business
    ActsAsTenant.with_tenant(customer_subscription.business) do
      # Create subscription transaction record
      transaction = customer_subscription.subscription_transactions.create!(
        business: customer_subscription.business,
        tenant_customer: customer_subscription.tenant_customer,
        amount: stripe_invoice['amount_paid'] / 100.0,
        stripe_invoice_id: stripe_invoice['id'],
        processed_date: Time.current,
        status: :completed,
        transaction_type: :billing
      )
      
      # Update subscription status and next billing date
      customer_subscription.update!(
        status: :active,
        next_billing_date: Time.at(stripe_invoice['period_end']).to_date
      )
      
      # Process the subscription (create order/booking)
      process_subscription_fulfillment(customer_subscription, transaction)
      
      Rails.logger.info "[CUSTOMER_SUB] Successfully processed payment for subscription #{customer_subscription.id}"
    end
  rescue => e
    Rails.logger.error "[CUSTOMER_SUB] Error processing successful payment for invoice #{stripe_invoice['id']}: #{e.message}"
  end

  # Handle failed subscription payment
  def self.handle_customer_subscription_payment_failed(stripe_invoice)
    Rails.logger.info "[CUSTOMER_SUB] Processing failed payment for invoice: #{stripe_invoice['id']}"
    
    stripe_subscription_id = stripe_invoice['subscription']
    return unless stripe_subscription_id
    
    # Find subscription across all tenants since webhooks don't have tenant context
    customer_subscription = CustomerSubscription.unscoped.find_by(stripe_subscription_id: stripe_subscription_id)
    return unless customer_subscription
    
    # Set tenant context for the subscription's business
    ActsAsTenant.with_tenant(customer_subscription.business) do
      # Create failed transaction record
      customer_subscription.subscription_transactions.create!(
        business: customer_subscription.business,
        tenant_customer: customer_subscription.tenant_customer,
        amount: stripe_invoice['amount_due'] / 100.0,
        stripe_invoice_id: stripe_invoice['id'],
        processed_date: Time.current,
        status: :failed,
        transaction_type: :billing,
        failure_reason: 'Payment failed'
      )
      
      # Update subscription status
      customer_subscription.update!(status: :payment_failed)
      
      # Send payment failure notification
      begin
        SubscriptionMailer.payment_failed(customer_subscription).deliver_later(queue: 'mailers')
      rescue => e
        Rails.logger.error "[EMAIL] Failed to send payment failure email for subscription #{customer_subscription.id}: #{e.message}"
      end
      
      Rails.logger.info "[CUSTOMER_SUB] Processed failed payment for subscription #{customer_subscription.id}"
    end
  rescue => e
    Rails.logger.error "[CUSTOMER_SUB] Error processing failed payment for invoice #{stripe_invoice['id']}: #{e.message}"
  end

  # Process subscription fulfillment (create orders/bookings)
  def self.process_subscription_fulfillment(customer_subscription, transaction)
    if customer_subscription.product_subscription?
      # Create order for product subscription
      SubscriptionOrderService.new(customer_subscription).process_subscription!
    elsif customer_subscription.service_subscription?
      # Create booking for service subscription
      SubscriptionBookingService.new(customer_subscription).process_subscription!
    end
  rescue => e
    Rails.logger.error "[CUSTOMER_SUB] Error processing fulfillment for subscription #{customer_subscription.id}: #{e.message}"
    # Don't re-raise - we don't want to fail the webhook for fulfillment issues
  end

  # Handle estimate deposit payment completion - this is when approve = paid
  # Payment success means the estimate is now officially approved
  def self.handle_estimate_payment_completion(session)
    Rails.logger.info "[ESTIMATE] Processing estimate payment completion for session #{session['id']}"

    business_id = session.dig('metadata', 'business_id')
    estimate_id = session.dig('metadata', 'estimate_id')
    invoice_id = session.dig('metadata', 'invoice_id')
    tenant_customer_id = session.dig('metadata', 'tenant_customer_id')

    unless business_id && estimate_id
      Rails.logger.error "[ESTIMATE] Missing required metadata in session #{session['id']}"
      return
    end

    business = Business.find_by(id: business_id)
    unless business
      Rails.logger.error "[ESTIMATE] Could not find business #{business_id} for session #{session['id']}"
      return
    end

    ActsAsTenant.with_tenant(business) do
      estimate = business.estimates.find_by(id: estimate_id)
      invoice = Invoice.find_by(id: invoice_id) if invoice_id
      tenant_customer = TenantCustomer.find_by(id: tenant_customer_id) if tenant_customer_id

      unless estimate
        Rails.logger.error "[ESTIMATE] Could not find estimate #{estimate_id} for session #{session['id']}"
        return
      end

      # Save the Stripe customer ID if we don't have it yet
      if session['customer'].present? && tenant_customer.present? && tenant_customer.stripe_customer_id.blank?
        tenant_customer.update!(stripe_customer_id: session['customer'])
        Rails.logger.info "[ESTIMATE] Saved Stripe customer ID #{session['customer']} for tenant customer #{tenant_customer.id}"
      end

      # Calculate fee amounts
      payment_amount = session['amount_total'] / 100.0
      amount_cents = session['amount_total']
      stripe_fee_amount = calculate_stripe_fee_cents(amount_cents) / 100.0
      platform_fee_amount = calculate_platform_fee_cents(amount_cents, business) / 100.0
      business_amount = (payment_amount - stripe_fee_amount - platform_fee_amount).round(2)

      # Create payment record
      payment = Payment.create!(
        business: business,
        invoice: invoice,
        tenant_customer: tenant_customer,
        amount: payment_amount,
        stripe_fee_amount: stripe_fee_amount,
        platform_fee_amount: platform_fee_amount,
        business_amount: business_amount,
        stripe_payment_intent_id: session['payment_intent'],
        stripe_customer_id: session['customer'],
        payment_method: :credit_card,
        status: :completed,
        paid_at: Time.current
      )

      # NOW mark estimate as approved (payment succeeded)
      estimate.update!(
        status: :approved,
        approved_at: Time.current,
        deposit_paid_at: Time.current,
        payment_intent_id: session['payment_intent']
      )

      # Mark invoice as paid
      invoice&.update!(status: :paid)

      Rails.logger.info "[ESTIMATE] Successfully approved estimate #{estimate.id} (#{estimate.estimate_number}) after payment #{payment.id}"

      # Send confirmation emails
      begin
        EstimateMailer.deposit_paid_confirmation(estimate).deliver_later(queue: 'mailers')
        Rails.logger.info "[ESTIMATE] Sent deposit paid confirmation for estimate #{estimate.id}"
      rescue => e
        Rails.logger.error "[ESTIMATE] Failed to send deposit confirmation email: #{e.message}"
      end

      # Notify business of approved estimate
      begin
        EstimateMailer.estimate_approved(estimate).deliver_later(queue: 'mailers')
        Rails.logger.info "[ESTIMATE] Sent estimate approved notification to business for estimate #{estimate.id}"
      rescue => e
        Rails.logger.error "[ESTIMATE] Failed to send business notification email: #{e.message}"
      end
    end
  rescue => e
    Rails.logger.error "[ESTIMATE] Error processing estimate payment for session #{session['id']}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end

  def self.handle_client_document_payment_completion(session)
    document_id = session.dig('metadata', 'client_document_id')
    # Use unscoped to find document without tenant context since we set it after
    document = ClientDocument.unscoped.find_by(id: document_id)
    return unless document

    ActsAsTenant.with_tenant(document.business) do
      payment = ensure_document_payment_record(document: document, session: session)
      ClientDocuments::WorkflowService.new(document).mark_payment_received!(
        payment_intent_id: session['payment_intent'],
        amount_cents: session['amount_total']
      )
      document.invoice&.update!(status: :paid)

      if document.metadata['booking_payload'].present?
        ClientDocuments::ExperienceBookingProcessor.process!(
          document: document,
          payment: payment,
          session: session
        )
      elsif document.documentable&.respond_to?(:handle_client_document_payment)
        document.documentable.handle_client_document_payment(document, payment)
      end
    end
  rescue => e
    Rails.logger.error "[CLIENT_DOCUMENT] Error processing payment for document #{document_id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end

  # Handle rental security deposit payment completion
  def self.handle_rental_deposit_payment_completion(session)
    Rails.logger.info "[RENTAL_DEPOSIT] Processing rental deposit payment for session #{session['id']}"

    business_id = session.dig('metadata', 'business_id')
    rental_booking_id = session.dig('metadata', 'rental_booking_id')
    customer_id = session.dig('metadata', 'customer_id')
    preauth_enabled = session.dig('metadata', 'preauth_enabled') == 'true' || session.dig('metadata', 'preauth_enabled') == true

    unless business_id && rental_booking_id
      Rails.logger.error "[RENTAL_DEPOSIT] Missing required metadata in session #{session['id']}"
      return
    end

    business = Business.find_by(id: business_id)
    unless business
      Rails.logger.error "[RENTAL_DEPOSIT] Could not find business #{business_id} for session #{session['id']}"
      return
    end

    ActsAsTenant.with_tenant(business) do
      rental_booking = business.rental_bookings.find_by(id: rental_booking_id)
      tenant_customer = TenantCustomer.find_by(id: customer_id) if customer_id

      unless rental_booking
        Rails.logger.error "[RENTAL_DEPOSIT] Could not find rental booking #{rental_booking_id} for session #{session['id']}"
        return
      end

      # Save the Stripe customer ID if we don't have it yet
      if session['customer'].present? && tenant_customer.present? && tenant_customer.stripe_customer_id.blank?
        tenant_customer.update!(stripe_customer_id: session['customer'])
        Rails.logger.info "[RENTAL_DEPOSIT] Saved Stripe customer ID #{session['customer']} for tenant customer #{tenant_customer.id}"
      end

      payment_intent_id = session['payment_intent']

      # Handle differently based on whether this is preauth or immediate capture
      if preauth_enabled
        # Preauthorization: mark as authorized (funds are held, not charged yet)
        if rental_booking.mark_deposit_authorized!(authorization_id: payment_intent_id)
          Rails.logger.info "[RENTAL_DEPOSIT] Successfully marked rental booking #{rental_booking.booking_number} deposit as authorized (preauth)"
        else
          Rails.logger.error "[RENTAL_DEPOSIT] Failed to mark rental booking #{rental_booking.booking_number} deposit as authorized"
        end
      else
        # Immediate capture: mark as paid (funds are charged immediately)
        if rental_booking.mark_deposit_paid!(payment_intent_id: payment_intent_id)
          Rails.logger.info "[RENTAL_DEPOSIT] Successfully marked rental booking #{rental_booking.booking_number} deposit as paid (immediate capture)"
        else
          Rails.logger.error "[RENTAL_DEPOSIT] Failed to mark rental booking #{rental_booking.booking_number} deposit as paid"
        end
      end
    end
  rescue => e
    Rails.logger.error "[RENTAL_DEPOSIT] Error processing rental deposit for session #{session['id']}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end

  # Handle tip payment completion
  def self.handle_tip_payment_completion(session)
    Rails.logger.info "[TIP] Processing tip payment completion for session #{session['id']}"
    
    business_id = session.dig('metadata', 'business_id')
    tip_id = session.dig('metadata', 'tip_id')
    tenant_customer_id = session.dig('metadata', 'tenant_customer_id')
    
    unless business_id && tip_id && tenant_customer_id
      Rails.logger.error "[TIP] Missing required metadata in session #{session['id']}"
      return
    end
    
    business = Business.find_by(id: business_id)
    unless business
      Rails.logger.error "[TIP] Could not find business #{business_id} for session #{session['id']}"
      return
    end
    
    ActsAsTenant.with_tenant(business) do
      tip = business.tips.find_by(id: tip_id)
      tenant_customer = business.tenant_customers.find_by(id: tenant_customer_id)
      
      unless tip && tenant_customer
        Rails.logger.error "[TIP] Could not find tip #{tip_id} or customer #{tenant_customer_id} for session #{session['id']}"
        return
      end
      
      # Save the Stripe customer ID if we don't have it yet
      if session['customer'].present? && tenant_customer.stripe_customer_id.blank?
        tenant_customer.update!(stripe_customer_id: session['customer'])
        Rails.logger.info "[TIP] Saved Stripe customer ID #{session['customer']} for tenant customer #{tenant_customer.id}"
      end
      
      # Use service helpers to calculate tip fees and net amount
      stripe_fee_amount   = calculate_tip_stripe_fee(tip.amount)
      platform_fee_amount = calculate_tip_platform_fee(tip.amount, business)
      business_amount     = calculate_tip_business_amount(tip.amount, business)

      # Update tip record with Stripe payment details and fees
      tip.update!(
        stripe_payment_intent_id: session['payment_intent'],
        stripe_customer_id: session['customer'],
        stripe_fee_amount:   stripe_fee_amount,
        platform_fee_amount: platform_fee_amount,
        business_amount:     business_amount,
        status: :completed,
        paid_at: Time.current
      )
      
      Rails.logger.info "[TIP] Successfully processed tip payment #{tip.id} for booking #{tip.booking_id} with fees: Stripe: $#{stripe_fee_amount}, Platform: $#{platform_fee_amount}"
    end
  rescue => e
    Rails.logger.error "[TIP] Error processing tip payment for session #{session['id']}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end

  def self.ensure_document_payment_record(document:, session:)
    existing_payment = Payment.find_by(stripe_payment_intent_id: session['payment_intent'])
    return existing_payment if existing_payment

    total_amount = session['amount_total'].to_f / 100.0
    amount_cents = session['amount_total']
    stripe_fee_amount   = calculate_stripe_fee_cents(amount_cents) / 100.0
    platform_fee_amount = calculate_platform_fee_cents(amount_cents, document.business) / 100.0
    business_amount     = (total_amount - stripe_fee_amount - platform_fee_amount).round(2)

    Payment.create!(
      business: document.business,
      invoice: document.invoice,
      tenant_customer: document.tenant_customer,
      amount: total_amount,
      stripe_fee_amount: stripe_fee_amount,
      platform_fee_amount: platform_fee_amount,
      business_amount: business_amount,
      stripe_payment_intent_id: session['payment_intent'],
      stripe_customer_id: session['customer'],
      payment_method: :credit_card,
      status: :completed,
      paid_at: Time.current
    )
  end

  # Handle booking creation after successful payment
  def self.handle_booking_payment_completion(session)
    Rails.logger.info "[BOOKING] Processing booking creation for session #{session['id']}"
    
    begin
      # Extract booking data from session metadata
      booking_data = JSON.parse(session.dig('metadata', 'booking_data'))
      business_id = session.dig('metadata', 'business_id')
      tenant_customer_id = session.dig('metadata', 'tenant_customer_id')
      
      business = Business.find_by(id: business_id)
      tenant_customer = TenantCustomer.find_by(id: tenant_customer_id)
      
      unless business && tenant_customer
        Rails.logger.error "[BOOKING] Could not find business (#{business_id}) or customer (#{tenant_customer_id})"
        return
      end
      
      Rails.logger.info "[BOOKING] Creating booking for customer ID #{tenant_customer.id} at business ID #{business.id}"
      
      ActiveRecord::Base.transaction do
        # Save the Stripe customer ID if we don't have it yet
        if session['customer'].present? && tenant_customer.stripe_customer_id.blank?
          tenant_customer.update!(stripe_customer_id: session['customer'])
          Rails.logger.info "[BOOKING] Saved Stripe customer ID #{session['customer']} for tenant customer #{tenant_customer.id}"
        end
        
        # Create the booking
        booking = business.bookings.create!(
          service_id: booking_data['service_id'],
          staff_member_id: booking_data['staff_member_id'],
          start_time: Time.parse(booking_data['start_time']),
          end_time: Time.parse(booking_data['end_time']),
          notes: booking_data['notes'],
          tenant_customer: tenant_customer,
          # Confirm by default when no policy exists, or auto confirm if enabled
          status: (business.booking_policy.nil? || business.booking_policy.auto_confirm_bookings?) ? :confirmed : :pending
        )
        
        # Create booking product add-ons if any
        if booking_data['booking_product_add_ons'].present?
          booking_data['booking_product_add_ons'].each do |addon_data|
            booking.booking_product_add_ons.create!(
              product_variant_id: addon_data['product_variant_id'],
              quantity: addon_data['quantity']
            )
          end
        end
        
        # Create invoice for the booking
        invoice = booking.build_invoice(
          tenant_customer: tenant_customer,
          business: business,
          tax_rate: business.default_tax_rate, # Assign default tax rate for proper tax calculation
          due_date: booking.start_time.to_date,
          status: :paid  # Mark as paid since payment was successful
        )
        invoice.save!
        
        # Create payment record
        total_amount = invoice.total_amount.to_f
        amount_cents = (total_amount * 100).to_i
        
        stripe_fee_amount   = calculate_stripe_fee_cents(amount_cents) / 100.0
        platform_fee_amount = calculate_platform_fee_cents(amount_cents, business) / 100.0
        business_amount     = (total_amount - stripe_fee_amount - platform_fee_amount).round(2)

        payment = Payment.create!(
          business: business,
          invoice: invoice,
          tenant_customer: tenant_customer,
          amount: total_amount,
          stripe_fee_amount:   stripe_fee_amount,
          platform_fee_amount: platform_fee_amount,
          business_amount:     business_amount,
          stripe_payment_intent_id: session['payment_intent'],
          stripe_customer_id: session['customer'],
          payment_method: :credit_card,
          status: :completed,
          paid_at: Time.current
        )
        
        Rails.logger.info "[BOOKING] Successfully created booking ##{booking.id} with payment ##{payment.id}"
        
        # Send payment confirmation (email + SMS) since booking invoice is now paid
        begin
          NotificationService.invoice_payment_confirmation(invoice, payment)
          Rails.logger.info "[NOTIFICATION] Sent payment confirmation for booking invoice ##{invoice.invoice_number}"
        rescue => e
          Rails.logger.error "[NOTIFICATION] Failed to send payment confirmation for booking invoice ##{invoice.invoice_number}: #{e.message}"
          # Don't fail the whole transaction for notification issues
        end
        
        # Send business notifications for the booking (email + SMS)
        begin
          NotificationService.business_new_booking(booking)
          Rails.logger.info "[NOTIFICATION] Scheduled business booking notification for Booking ##{booking.id}"
        rescue => e
          Rails.logger.error "[NOTIFICATION] Failed to schedule business booking notification for Booking ##{booking.id}: #{e.message}"
          # Don't fail the whole transaction for notification issues
        end
        
        # Send business payment notification (email + SMS)
        begin
          NotificationService.business_payment_received(payment)
          Rails.logger.info "[NOTIFICATION] Scheduled business payment notification for Booking ##{booking.id} payment"
        rescue => e
          Rails.logger.error "[NOTIFICATION] Failed to schedule business payment notification for Booking ##{booking.id}: #{e.message}"
          # Don't fail the whole transaction for notification issues
        end
      end
      
    rescue JSON::ParserError => e
      Rails.logger.error "[BOOKING] Failed to parse booking data from session #{session['id']}: #{e.message}"
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "[BOOKING] Database validation failed for session #{session['id']}: #{e.message}"
    rescue => e
      Rails.logger.error "[BOOKING] Unexpected error processing booking for session #{session['id']}: #{e.message}"
      # Re-raise to ensure webhook fails and can be retried
      raise e
    end
  end

  # Handle business registration completion after successful Stripe payment
  def self.handle_business_registration_completion(session)
    Rails.logger.info "[REGISTRATION] Processing business registration completion for session #{session['id']}"

    begin
      # Extract registration data from session metadata
      user_data = JSON.parse(session.dig('metadata', 'user_data'))
      business_data = JSON.parse(session.dig('metadata', 'business_data'))
      sidebar_items = JSON.parse(session.dig('metadata', 'sidebar_items') || '[]')
      sidebar_customized = session.dig('metadata', 'sidebar_customized') || "0"

      Rails.logger.info "[REGISTRATION] Creating business: #{business_data['name']} (#{business_data['tier']})"

      ActiveRecord::Base.transaction do
        # Create business first
        business = Business.create!(business_data)
        Rails.logger.info "[REGISTRATION] Created business ##{business.id}"

        # Create user with business association
        user = User.create!(user_data.merge(
          business_id: business.id,
          role: :manager
        ))
        Rails.logger.info "[REGISTRATION] Created user ##{user.id} for business ##{business.id}"

        # Update business with Stripe customer ID from the session
        if session['customer']
          business.update!(stripe_customer_id: session['customer'])
        end

        # Create subscription record if this was a paid tier registration
        if session['subscription'] && business.tier.in?(['standard', 'premium'])
          create_subscription_record(business, session['subscription'])
        end

        # Set up all the default records for the business
        setup_business_defaults_from_webhook(business, user, sidebar_items, sidebar_customized)

        Rails.logger.info "[REGISTRATION] Successfully completed business registration for #{business.name} (ID: #{business.id})"
      end

    rescue JSON::ParserError => e
      Rails.logger.error "[REGISTRATION] Failed to parse registration data from session #{session['id']}: #{e.message}"
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "[REGISTRATION] Database validation failed for session #{session['id']}: #{e.message}"
    rescue => e
      Rails.logger.error "[REGISTRATION] Unexpected error processing registration for session #{session['id']}: #{e.message}"
      # Re-raise to ensure webhook fails and can be retried
      raise e
    end
  end

  # Set up default records for a newly created business (called from webhook)
  def self.setup_business_defaults_from_webhook(business, user, sidebar_items = [], sidebar_customized = "0")
    # Create staff member for the business owner
    business.staff_members.create!(
      user: user,
      name: user.full_name,
      email: user.email,
      phone: business.phone,
      active: true
    )
    Rails.logger.info "[REGISTRATION] Created staff member for user ##{user.id}"

    # Create default location using business address
    create_default_location_from_webhook(business)

    # Create sidebar item preferences for the owner
    create_sidebar_items_from_registration(user, sidebar_items, sidebar_customized)

    # Set up Stripe Connect account for paid tiers
    if business.tier.in?(['standard', 'premium'])
      begin
        create_connect_account(business)
        Rails.logger.info "[REGISTRATION] Created Stripe Connect account for business ##{business.id}"
      rescue Stripe::StripeError => e
        Rails.logger.error "[REGISTRATION] Failed to create Stripe Connect account for business ##{business.id}: #{e.message}"
        # Don't fail the whole registration for this
      end
    end

    Rails.logger.info "[REGISTRATION] Completed setup for business ##{business.id}"
  end

  # Create default location for business (called from webhook)
  def self.create_default_location_from_webhook(business)
    # Default business hours (9am-5pm Monday-Friday, 10am-2pm Saturday, closed Sunday)
    default_hours = {
      "monday" => { "open" => "09:00", "close" => "17:00", "closed" => false },
      "tuesday" => { "open" => "09:00", "close" => "17:00", "closed" => false },
      "wednesday" => { "open" => "09:00", "close" => "17:00", "closed" => false },
      "thursday" => { "open" => "09:00", "close" => "17:00", "closed" => false },
      "friday" => { "open" => "09:00", "close" => "17:00", "closed" => false },
      "saturday" => { "open" => "10:00", "close" => "14:00", "closed" => false },
      "sunday" => { "open" => "00:00", "close" => "00:00", "closed" => true }
    }
    
    business.locations.create!(
      name: "Main Location",
      address: business.address,
      city: business.city,
      state: business.state,
      zip: business.zip,
      hours: default_hours
    )
    
    Rails.logger.info "[REGISTRATION] Created default location for business ##{business.id}"
  rescue => e
    Rails.logger.error "[REGISTRATION] Failed to create default location for business ##{business.id}: #{e.message}"
    # Don't fail the whole registration for this
  end

  # Create sidebar item preferences for a newly registered user (called from webhook)
  def self.create_sidebar_items_from_registration(user, selected_items, customized = "0")
    # If user didn't customize sidebar (didn't interact with the section), use defaults
    # The sidebar system will show all defaults when no UserSidebarItem records exist
    return unless customized == "1"

    # User explicitly customized their sidebar - create records for all items
    # Even if selected_items is empty (user deselected all), we create records with visible: false
    selected_items ||= []

    # Get all default items (this returns the master list of 21 items)
    all_items = [
      'dashboard', 'bookings', 'estimates', 'website', 'website_builder',
      'transactions', 'payments', 'staff', 'services', 'products',
      'rentals', 'rental_bookings', 'shipping_methods', 'tax_rates',
      'customers', 'referrals', 'loyalty', 'platform',
      'promotions', 'customer_subscriptions', 'settings'
    ]

    # Create records for all items, marking visibility based on selection
    all_items.each_with_index do |item_key, index|
      is_visible = selected_items.include?(item_key)

      user.user_sidebar_items.create!(
        item_key: item_key,
        position: index,
        visible: is_visible
      )
    end

    Rails.logger.info "[REGISTRATION] Created #{user.user_sidebar_items.count} sidebar items for user ##{user.id}"
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "[REGISTRATION] Failed to create sidebar items for user ##{user.id}: #{e.message}"
    # Don't fail the whole registration for this
  end

  # Create subscription record for the business
  def self.create_subscription_record(business, stripe_subscription_id)
    begin
      # Retrieve subscription details from Stripe
      stripe_sub = Stripe::Subscription.retrieve(stripe_subscription_id)
      
      # Determine plan name from tier
      plan_name = case business.tier
                  when 'standard' then 'Standard Plan'
                  when 'premium' then 'Premium Plan'
                  else business.tier.titleize
                  end
      
      # Create subscription record
      subscription = business.subscriptions.create!(
        plan_name: plan_name,
        stripe_subscription_id: stripe_subscription_id,
        status: stripe_sub.status,
        current_period_end: Time.at(stripe_sub.current_period_end).to_datetime
      )
      
      Rails.logger.info "[REGISTRATION] Created subscription record ##{subscription.id} for business ##{business.id}"
      subscription
      
    rescue Stripe::StripeError => e
      Rails.logger.error "[REGISTRATION] Failed to retrieve Stripe subscription #{stripe_subscription_id}: #{e.message}"
      # Create a basic subscription record without Stripe details
      business.subscriptions.create!(
        plan_name: business.tier.titleize,
        stripe_subscription_id: stripe_subscription_id,
        status: 'active'
      )
    rescue => e
      Rails.logger.error "[REGISTRATION] Failed to create subscription record for business ##{business.id}: #{e.message}"
      # Don't fail the whole registration for this
    end
  end

  # Handle updates to Stripe Connect accounts
  def self.handle_account_updated(account_data)
    business = Business.find_by(stripe_account_id: account_data['id'])
    return unless business
    Rails.logger.info "Stripe Connect account updated for business id=#{business.id}"  
    # Optionally, you could update a business flag here once onboarding is complete
  end

  def self.handle_payment_completion(session)
    Rails.logger.info "Processing Stripe checkout session completion: #{session.id}"
    
    # Find the invoice based on client_reference_id
    invoice = Invoice.find_by(id: session.client_reference_id)
    unless invoice
      Rails.logger.error "Invoice not found for session: #{session.id}"
      return { success: false, error: "Invoice not found" }
    end

    # Get the payment intent from the session
    payment_intent_id = session.payment_intent
    payment_intent = Stripe::PaymentIntent.retrieve(
      payment_intent_id,
      stripe_account: invoice.business.stripe_account_id
    )

    # Calculate amounts and fees
    amount_received = payment_intent.amount_received / 100.0
    stripe_fee_amount = (payment_intent.charges.data.first&.balance_transaction&.fee || 0) / 100.0
    
    # Extract tip amount from metadata or calculate from difference
    tip_amount = if session.metadata&.dig('tip_amount')
                   session.metadata['tip_amount'].to_f
                 elsif invoice.tip_amount && invoice.tip_amount > 0
                   invoice.tip_amount
                 else
                   0.0
                 end

    # Calculate platform fee and net business amount
    platform_fee_amount = calculate_platform_fee(amount_received - tip_amount)
    business_amount = (amount_received - stripe_fee_amount - platform_fee_amount).round(2)

    # Create payment record
    payment = invoice.payments.build(
      stripe_payment_intent_id: payment_intent_id,
      amount: amount_received,
      tip_amount: tip_amount,
      stripe_fee_amount: stripe_fee_amount,
      platform_fee_amount: platform_fee_amount,
      business_amount: business_amount,
      status: :completed,
      payment_method: :credit_card,
      business: invoice.business,
      tenant_customer: invoice.tenant_customer
    )

    ActiveRecord::Base.transaction do
      # Save the payment
      payment.save!

      # Update invoice status
      invoice.update!(
        status: :paid
      )

      # Update order if present
      if invoice.order
        invoice.order.update!(
          status: :paid,
          tip_amount: tip_amount
        )
      end

      # Create tip record if tip amount exists
      if tip_amount > 0
        create_tip_record_from_payment(payment, invoice)
      end

      # Send confirmation notifications (email + SMS)
      if invoice.tenant_customer&.email
        NotificationService.invoice_payment_confirmation(invoice, payment)
      end

      Rails.logger.info "Payment processed successfully for invoice #{invoice.id}"
    end

    { success: true, payment: payment }
  rescue => e
    Rails.logger.error "Error processing payment: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    { success: false, error: e.message }
  end

  # Create tip record from completed payment
  def self.create_tip_record_from_payment(payment, invoice)
    return unless payment.tip_amount && payment.tip_amount > 0
    
    # Determine the context for the tip
    if invoice.order
      # Order-based tip
      create_order_tip(payment, invoice)
    elsif invoice.booking
      # Booking-based tip (experience service)
      create_booking_tip(payment, invoice)
    else
      # General invoice tip
      create_invoice_tip(payment, invoice)
    end
  end

  def self.create_order_tip(payment, invoice)
    # For order tips, we need a booking - use the booking associated with the order
    booking = invoice.order&.booking
    return unless booking
    
    tip = Tip.create!(
      business: invoice.business,
      tenant_customer: invoice.tenant_customer,
      booking: booking,
      amount: payment.tip_amount,
      status: :completed
    )
    
    Rails.logger.info "Created order tip #{tip.id} for amount #{payment.tip_amount}"
    tip
  end

  def self.create_booking_tip(payment, invoice)
    return unless invoice.booking
    
    tip = Tip.create!(
      business: invoice.business,
      tenant_customer: invoice.tenant_customer,
      booking: invoice.booking,
      amount: payment.tip_amount,
      status: :completed
    )
    
    Rails.logger.info "Created booking tip #{tip.id} for amount #{payment.tip_amount}"
    tip
  end

  def self.create_invoice_tip(payment, invoice)
    # For invoice tips, we need a booking - skip if no booking available
    return unless invoice.booking
    
    tip = Tip.create!(
      business: invoice.business,
      tenant_customer: invoice.tenant_customer,
      booking: invoice.booking,
      amount: payment.tip_amount,
      status: :completed
    )
    
    Rails.logger.info "Created invoice tip #{tip.id} for amount #{payment.tip_amount}"
    tip
  end

  # Calculate tip-specific fees
  def self.calculate_tip_stripe_fee(tip_amount)
    # Stripe fee: 2.9% + $0.30 per transaction (prorated for tip portion)
    ((tip_amount * 0.029) + 0.30).round(2)
  end

  def self.calculate_tip_platform_fee(tip_amount, business = nil)
    # Platform takes the same fee from tips as other payments
    business_for_calc = business || ActsAsTenant.current_tenant
    
    # Always treat tip_amount as dollars and convert to cents
    amount_cents = (tip_amount * 100).to_i
    fee_cents = calculate_platform_fee_cents(amount_cents, business_for_calc)
    fee_cents / 100.0
  end

  def self.calculate_tip_business_amount(tip_amount, business = nil)
    # Calculate actual net amount business receives after all fees
    tip_amount - calculate_tip_stripe_fee(tip_amount) - calculate_tip_platform_fee(tip_amount, business)
  end

  # Calculate platform fee for general use (used by tests)
  def self.calculate_platform_fee(amount)
    # Convert to cents if needed and calculate, then convert back
    if amount < 100 # Assume it's in dollars if less than 100
      amount_cents = (amount * 100).to_i
      fee_cents = calculate_platform_fee_cents(amount_cents, ActsAsTenant.current_tenant)
      fee_cents / 100.0
    else # Assume it's already in cents
      calculate_platform_fee_cents(amount, ActsAsTenant.current_tenant) / 100.0
    end
  end

  # Handle subscription signup completion after successful Stripe checkout
  def self.handle_subscription_signup_completion(session)
    Rails.logger.info "[SUBSCRIPTION] Processing subscription signup completion for session #{session['id']}"
    
    begin
      # Extract subscription data from session metadata
      subscription_data = JSON.parse(session.dig('metadata', 'subscription_data'))
      business_id = session.dig('metadata', 'business_id')
      tenant_customer_id = session.dig('metadata', 'tenant_customer_id')
      
      business = Business.find_by(id: business_id)
      tenant_customer = TenantCustomer.find_by(id: tenant_customer_id)
      
      unless business && tenant_customer
        Rails.logger.error "[SUBSCRIPTION] Could not find business (#{business_id}) or customer (#{tenant_customer_id})"
        return
      end
      
      Rails.logger.info "[SUBSCRIPTION] Creating subscription for customer ID #{tenant_customer.id} at business ID #{business.id}"
      
      ActiveRecord::Base.transaction do
        # Save the Stripe customer ID if we don't have it yet
        if session['customer'].present? && tenant_customer.stripe_customer_id.blank?
          tenant_customer.update!(stripe_customer_id: session['customer'])
          Rails.logger.info "[SUBSCRIPTION] Saved Stripe customer ID #{session['customer']} for tenant customer #{tenant_customer.id}"
        end
        
        # Create the customer subscription record
        customer_subscription = business.customer_subscriptions.create!(
          tenant_customer: tenant_customer,
          subscription_type: subscription_data['subscription_type'],
          product_id: subscription_data['subscription_type'] == 'product' ? subscription_data['item_id'] : nil,
          service_id: subscription_data['subscription_type'] == 'service' ? subscription_data['item_id'] : nil,
          quantity: subscription_data['quantity'] || 1,
          frequency: subscription_data['frequency'] || 'monthly',
          subscription_price: subscription_data['subscription_price'],
          status: :active,
          stripe_subscription_id: session['subscription'],
          customer_preferences: subscription_data['customer_preferences'] || {},
          start_date: Date.current,
          next_billing_date: Date.current + 1.month
        )
        
        # Create initial transaction record
        customer_subscription.subscription_transactions.create!(
          amount: subscription_data['subscription_price'],
          stripe_invoice_id: nil, # Will be updated by webhook
          processed_date: Time.current,
          status: :completed,
          transaction_type: :signup
        )
        
        Rails.logger.info "[SUBSCRIPTION] Successfully created subscription ##{customer_subscription.id}"
        
        # Send confirmation emails
        begin
          SubscriptionMailer.signup_confirmation(customer_subscription).deliver_later(queue: 'mailers')
          Rails.logger.info "[EMAIL] Sent subscription confirmation email for subscription ##{customer_subscription.id}"
        rescue => e
          Rails.logger.error "[EMAIL] Failed to send subscription confirmation email for subscription ##{customer_subscription.id}: #{e.message}"
          # Don't fail the whole transaction for email issues
        end

        # Send business notification
        begin
          BusinessMailer.new_subscription_notification(customer_subscription).deliver_later(queue: 'mailers')
          Rails.logger.info "[EMAIL] Scheduled business subscription notification for subscription ##{customer_subscription.id}"
        rescue => e
          Rails.logger.error "[EMAIL] Failed to schedule business subscription notification for subscription ##{customer_subscription.id}: #{e.message}"
          # Don't fail the whole transaction for email issues
        end
      end
      
    rescue JSON::ParserError => e
      Rails.logger.error "[SUBSCRIPTION] Failed to parse subscription data from session #{session['id']}: #{e.message}"
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "[SUBSCRIPTION] Database validation failed for session #{session['id']}: #{e.message}"
    rescue => e
      Rails.logger.error "[SUBSCRIPTION] Unexpected error processing subscription for session #{session['id']}: #{e.message}"
      # Re-raise to ensure webhook fails and can be retried
      raise e
    end
  end

  # Extract tip amount from payment intent for payment link tipping
  def self.extract_tip_amount_from_payment_intent(payment_intent)
    # For Stripe Payment Links with tipping, the tip amount is included in the charges
    # The tip amount can be found in the charge's metadata or calculated from amount difference
    charges = payment_intent.dig('charges', 'data') || []
    return 0.0 if charges.empty?
    
    charge = charges.first
    
    # Check if this charge has tip information in metadata
    tip_amount_cents = charge.dig('metadata', 'tip_amount_cents')&.to_i
    if tip_amount_cents && tip_amount_cents > 0
      return tip_amount_cents / 100.0
    end
    
    # For Payment Links, tip amount might be in the charge description or amount breakdown
    # Check if the charge description mentions tipping
    description = charge['description'] || ''
    if description.include?('tip') || description.include?('gratuity')
      # Try to extract tip amount from calculation_details if available
      # This is a best-effort extraction - Stripe provides tip amounts in charge metadata
      total_amount = charge['amount'] || 0
      base_amount = payment_intent.dig('metadata', 'base_amount_cents')&.to_i || 0
      
      if base_amount > 0 && total_amount > base_amount
        tip_amount = (total_amount - base_amount) / 100.0
        Rails.logger.info "[TIP] Extracted tip amount $#{tip_amount} from payment intent #{payment_intent['id']}"
        return tip_amount
      end
    end
    
    # Default to no tip if we can't extract it
    0.0
  rescue => e
    Rails.logger.error "[TIP] Failed to extract tip amount from payment intent #{payment_intent['id']}: #{e.message}"
    0.0
  end
end
