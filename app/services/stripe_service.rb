# frozen_string_literal: true

class StripeService
  # This service handles integration with the Stripe payment gateway
  
  # Configure API key for all Stripe calls
  def self.configure_stripe_api_key
    stripe_credentials = Rails.application.credentials.stripe || {}
    Stripe.api_key = stripe_credentials[:secret_key] || ENV['STRIPE_SECRET_KEY']
  end

  # Create a Stripe Connect Express account for a business
  def self.create_connect_account(business)
    configure_stripe_api_key
    account = Stripe::Account.create(
      type: 'express',
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

  # Create a Stripe Checkout session for invoice payment
  def self.create_payment_checkout_session(invoice:, success_url:, cancel_url:)
    configure_stripe_api_key
    business = invoice.business
    customer = ensure_stripe_customer_for_tenant(invoice.tenant_customer)

    total_amount = invoice.total_amount.to_f
    
    # Stripe requires a minimum charge amount of $0.50 USD
    if total_amount < 0.50
      raise ArgumentError, "Payment amount must be at least $0.50 USD. Current amount: $#{total_amount}"
    end
    
    amount_cents = (total_amount * 100).to_i
    platform_fee_cents = calculate_platform_fee_cents(amount_cents, business)

    # Create the checkout session
    session = Stripe::Checkout::Session.create(
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
      customer: customer.id,
      payment_intent_data: {
        application_fee_amount: platform_fee_cents,
        transfer_data: { destination: business.stripe_account_id },
        metadata: { 
          business_id: business.id, 
          invoice_id: invoice.id,
          tenant_customer_id: invoice.tenant_customer.id
        }
      },
      metadata: { 
        business_id: business.id, 
        invoice_id: invoice.id,
        tenant_customer_id: invoice.tenant_customer.id
      }
    )

    # Create a payment record to track this
    payment = Payment.create!(
      business: business,
      invoice: invoice,
      order: invoice.order,
      tenant_customer: invoice.tenant_customer,
      amount: total_amount,
      stripe_fee_amount: calculate_stripe_fee_cents(amount_cents) / 100.0,
      platform_fee_amount: platform_fee_cents / 100.0,
      business_amount: (total_amount - calculate_stripe_fee_cents(amount_cents) / 100.0 - platform_fee_cents / 100.0).round(2),
      stripe_payment_intent_id: session.payment_intent,
      stripe_customer_id: customer.id,
      status: :pending
    )

    { session: session, payment: payment }
  end

  # Create a payment intent for an invoice or order
  def self.create_payment_intent(invoice:, order: nil, payment_method_id: nil)
    configure_stripe_api_key
    business = invoice.business
    # Ensure Stripe customer for tenant
    customer = ensure_stripe_customer_for_tenant(invoice.tenant_customer)

    total_amount = invoice.total_amount.to_f
    
    # Stripe requires a minimum charge amount of $0.50 USD
    if total_amount < 0.50
      raise ArgumentError, "Payment amount must be at least $0.50 USD. Current amount: $#{total_amount}"
    end
    
    amount_cents = (total_amount * 100).to_i
    stripe_fee_cents = calculate_stripe_fee_cents(amount_cents)
    platform_fee_cents = calculate_platform_fee_cents(amount_cents, business)

    intent = Stripe::PaymentIntent.create(
      amount: amount_cents,
      currency: 'usd',
      customer: customer.id,
      payment_method: payment_method_id,
      confirm: payment_method_id.present?,
      metadata: { business_id: business.id, invoice_id: invoice.id, order_id: order&.id },
      application_fee_amount: platform_fee_cents,
      transfer_data: { destination: business.stripe_account_id }
    )

    payment = Payment.create!(
      business: business,
      invoice: invoice,
      order: order,
      tenant_customer: invoice.tenant_customer,
      amount: total_amount,
      stripe_fee_amount: stripe_fee_cents / 100.0,
      platform_fee_amount: platform_fee_cents / 100.0,
      business_amount: (total_amount - stripe_fee_cents / 100.0 - platform_fee_cents / 100.0).round(2),
      stripe_payment_intent_id: intent.id,
      stripe_customer_id: customer.id,
      status: :pending
    )

    { id: intent.id, client_secret: intent.client_secret, payment: payment }
  end

  # Process raw webhook payload (as JSON string)
  def self.process_webhook(event_json)
    configure_stripe_api_key
    event = JSON.parse(event_json)
    case event['type']
    when 'payment_intent.succeeded'
      handle_successful_payment(event['data']['object'])
    when 'payment_intent.payment_failed'
      handle_failed_payment(event['data']['object'])
    when 'charge.refunded'
      handle_refund(event['data']['object'])
    when 'account.updated'
      handle_account_updated(event['data']['object'])
    when 'checkout.session.completed'
      handle_checkout_session_completed(event['data']['object'])
    when 'customer.subscription.deleted', 'customer.subscription.updated', 'customer.subscription.created'
      handle_subscription_event(event['data']['object'])
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
    refund = Stripe::Refund.create(params)
    payment.update!(status: :refunded, refunded_amount: (refund.amount_refunded / 100.0), refund_reason: reason)
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

  private

  # Calculate Stripe's fee in cents (3% + 30¢)
  def self.calculate_stripe_fee_cents(amount_cents)
    (amount_cents * 0.03).round + 30
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
  def self.ensure_stripe_customer_for_tenant(tenant)
    return Stripe::Customer.retrieve(tenant.stripe_customer_id) if tenant.stripe_customer_id.present?
    customer = Stripe::Customer.create(email: tenant.email, name: tenant.name, metadata: { tenant_customer_id: tenant.id })
    tenant.update!(stripe_customer_id: customer.id)
    customer
  end

  # Retrieve or create Stripe Customer for business (for subscription billing)
  def self.ensure_stripe_customer_for_business(business)
    return Stripe::Customer.retrieve(business.stripe_customer_id) if business.stripe_customer_id.present?
    customer = Stripe::Customer.create(email: business.email, name: business.name, metadata: { business_id: business.id })
    business.update!(stripe_customer_id: customer.id)
    customer
  end

  # Handle successful checkout session completion for payments
  def self.handle_checkout_session_completed(session)
    # Check if this is a payment (not subscription) by looking for invoice_id in metadata
    invoice_id = session.dig('metadata', 'invoice_id')
    return unless invoice_id

    payment = Payment.find_by(stripe_payment_intent_id: session['payment_intent'])
    return unless payment

    # Mark payment as completed
    payment.update!(status: :completed, paid_at: Time.current, payment_method: :credit_card)
    payment.invoice.mark_as_paid! if payment.invoice&.pending?
    
    # Update order status if applicable
    if (order = payment.order)
      new_status = order.payment_required? ? :paid : :processing
      order.update!(status: new_status)
    end
  end

  def self.handle_successful_payment(pi)
    payment = Payment.find_by(stripe_payment_intent_id: pi['id'])
    return unless payment
    
    # Determine payment method from Stripe data
    payment_method = case pi.dig('charges', 'data', 0, 'payment_method_details', 'type')
                    when 'card' then :credit_card
                    when 'us_bank_account' then :bank_transfer
                    when 'paypal' then :paypal
                    else :other
                    end
    
    payment.update!(status: :completed, paid_at: Time.current, payment_method: payment_method)
    payment.invoice.mark_as_paid! if payment.invoice&.pending?
    # Update order status if applicable
    if (order = payment.order)
      # For product or experience orders, mark as paid; for services, mark as processing
      new_status = order.payment_required? ? :paid : :processing
      order.update!(status: new_status)
    end
  end

  def self.handle_failed_payment(pi)
    payment = Payment.find_by(stripe_payment_intent_id: pi['id'])
    return unless payment
    payment.update!(status: :failed, failure_reason: pi['last_payment_error']&.dig('message'))
  end

  def self.handle_refund(charge)
    payment = Payment.find_by(stripe_charge_id: charge['id'])
    return unless payment
    refunded_amt = charge['amount_refunded'] / 100.0
    reason = charge['refunds']&.dig('data')&.first&.dig('reason')
    payment.update!(status: :refunded, refunded_amount: refunded_amt, refund_reason: reason)
  end

  def self.handle_subscription_event(sub)
    if sub['status'] == 'canceled'
      handle_subscription_suspension(sub)
    else
      record = Subscription.find_by(stripe_subscription_id: sub['id'])
      return unless record
      record.update!(status: sub['status'], current_period_end: Time.at(sub['current_period_end']).to_datetime)
    end
  end

  # Handle updates to Stripe Connect accounts
  def self.handle_account_updated(account_data)
    business = Business.find_by(stripe_account_id: account_data['id'])
    return unless business
    Rails.logger.info "Stripe Connect account updated for business id=#{business.id}"  
    # Optionally, you could update a business flag here once onboarding is complete
  end
end
