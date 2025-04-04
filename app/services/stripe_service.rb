class StripeService
  # This service handles integration with the Stripe payment gateway
  
  def self.create_customer(customer)
    # Skip if the customer already has a Stripe ID
    return customer.stripe_customer_id if customer.stripe_customer_id.present?
    
    # In a real implementation, this would use the Stripe API
    # stripe_customer = Stripe::Customer.create(
    #   email: customer.email,
    #   name: customer.name,
    #   phone: customer.phone,
    #   metadata: {
    #     business_id: customer.business_id,
    #     customer_id: customer.id
    #   }
    # )
    
    # Placeholder implementation
    stripe_customer_id = "cus_#{SecureRandom.hex(10)}"
    
    # Save the Stripe customer ID to our customer record
    customer.update(stripe_customer_id: stripe_customer_id)
    
    stripe_customer_id
  end
  
  def self.create_payment_intent(booking, amount, payment_method_id = nil)
    customer = booking.customer
    stripe_customer_id = create_customer(customer)
    
    # In a real implementation, this would use the Stripe API
    # payment_intent = Stripe::PaymentIntent.create(
    #   amount: (amount * 100).to_i, # Convert to cents
    #   currency: 'usd',
    #   customer: stripe_customer_id,
    #   payment_method: payment_method_id,
    #   confirm: payment_method_id.present?,
    #   metadata: {
    #     business_id: booking.business_id,
    #     booking_id: booking.id,
    #     customer_id: customer.id
    #   }
    # )
    
    # Placeholder implementation
    payment_intent_id = "pi_#{SecureRandom.hex(10)}"
    client_secret = "#{payment_intent_id}_secret_#{SecureRandom.hex(10)}"
    
    # Create a new payment record in our system
    payment = Payment.create(
      booking: booking,
      customer: customer,
      amount: amount,
      payment_method: :credit_card,
      status: :pending,
      stripe_payment_intent_id: payment_intent_id,
      business_id: booking.business_id
    )
    
    { id: payment_intent_id, client_secret: client_secret, payment: payment }
  end
  
  def self.process_webhook(event_json)
    # This would handle Stripe webhook events
    # event = Stripe::Event.construct_from(event_json)
    
    # Placeholder implementation
    event = JSON.parse(event_json)
    
    case event['type']
    when 'payment_intent.succeeded'
      handle_successful_payment(event['data']['object'])
    when 'payment_intent.payment_failed'
      handle_failed_payment(event['data']['object'])
    end
    
    true
  end
  
  private
  
  def self.handle_successful_payment(payment_intent)
    payment = Payment.find_by(stripe_payment_intent_id: payment_intent['id'])
    return unless payment
    
    payment.mark_as_completed!
    
    # Update the booking status if needed
    if payment.booking
      payment.booking.update(status: :confirmed) if payment.booking.pending?
    end
    
    # Create an invoice if needed
    unless Invoice.exists?(booking_id: payment.booking_id)
      Invoice.create(
        customer: payment.customer,
        booking: payment.booking,
        amount: payment.amount,
        due_date: Date.current,
        status: :paid,
        paid_at: Time.current,
        business_id: payment.business_id
      )
    end
  end
  
  def self.handle_failed_payment(payment_intent)
    payment = Payment.find_by(stripe_payment_intent_id: payment_intent['id'])
    return unless payment
    
    payment.update(
      status: :failed,
      error_message: payment_intent['last_payment_error']&.[]('message')
    )
  end
end
