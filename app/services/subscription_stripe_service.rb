# frozen_string_literal: true

class SubscriptionStripeService
  attr_reader :customer_subscription, :business, :tenant_customer
  
  def initialize(customer_subscription)
    @customer_subscription = customer_subscription
    @business = customer_subscription.business
    @tenant_customer = customer_subscription.tenant_customer
  end
  
  def create_stripe_subscription!
    return false unless customer_subscription.active?
    return false if customer_subscription.stripe_subscription_id.present?
    
    begin
      # Ensure customer has a Stripe customer ID
      stripe_customer = ensure_stripe_customer
      return false unless stripe_customer
      
      # Create the subscription in Stripe
      stripe_subscription = create_stripe_subscription_object(stripe_customer)
      
      if stripe_subscription
        # Update our subscription with Stripe details
        customer_subscription.update!(
          stripe_subscription_id: stripe_subscription.id
        )
        
        Rails.logger.info "[STRIPE SUBSCRIPTION] Created Stripe subscription #{stripe_subscription.id} for customer subscription #{customer_subscription.id}"
        true
      else
        false
      end
    rescue => e
      Rails.logger.error "[STRIPE SUBSCRIPTION] Error creating Stripe subscription for #{customer_subscription.id}: #{e.message}"
      false
    end
  end
  
  def update_stripe_subscription!
    return false unless customer_subscription.stripe_subscription_id.present?
    
    begin
      stripe_subscription = Stripe::Subscription.retrieve(customer_subscription.stripe_subscription_id, {
        stripe_account: business.stripe_account_id
      })
      
      # Update subscription details
      stripe_subscription = Stripe::Subscription.update(
        customer_subscription.stripe_subscription_id,
        {
          items: [{
            id: stripe_subscription.items.data[0].id,
            price: get_stripe_price_id,
            quantity: customer_subscription.quantity || 1
          }],
          proration_behavior: 'create_prorations'
        },
        {
          stripe_account: business.stripe_account_id
        }
      )
      
      # Update local subscription (only update attributes that exist)
      # Note: CustomerSubscription model only has stripe_subscription_id, not stripe_status or period dates
      
      Rails.logger.info "[STRIPE SUBSCRIPTION] Updated Stripe subscription #{stripe_subscription.id}"
      true
    rescue => e
      Rails.logger.error "[STRIPE SUBSCRIPTION] Error updating Stripe subscription #{customer_subscription.stripe_subscription_id}: #{e.message}"
      false
    end
  end
  
  def cancel_stripe_subscription!
    return false unless customer_subscription.stripe_subscription_id.present?
    
    begin
      stripe_subscription = Stripe::Subscription.cancel(customer_subscription.stripe_subscription_id, {}, {
        stripe_account: business.stripe_account_id
      })
      
      # Update local subscription
      customer_subscription.update!(
        status: :cancelled,
        cancelled_at: Time.current
      )
      
      Rails.logger.info "[STRIPE SUBSCRIPTION] Cancelled Stripe subscription #{stripe_subscription.id}"
      true
    rescue => e
      Rails.logger.error "[STRIPE SUBSCRIPTION] Error cancelling Stripe subscription #{customer_subscription.stripe_subscription_id}: #{e.message}"
      false
    end
  end


  
  def sync_stripe_subscription!
    return false unless customer_subscription.stripe_subscription_id.present?
    
    begin
      stripe_subscription = Stripe::Subscription.retrieve(customer_subscription.stripe_subscription_id, {
        stripe_account: business.stripe_account_id
      })
      
      # Update status based on Stripe status
      case stripe_subscription.status
      when 'active'
        customer_subscription.update!(status: :active) unless customer_subscription.active?
      when 'canceled', 'cancelled'
        customer_subscription.update!(status: :cancelled, cancelled_at: Time.current)
      when 'past_due'
        # Note: CustomerSubscription doesn't have past_due status, map to failed
        customer_subscription.update!(status: :failed)
      when 'unpaid'
        customer_subscription.update!(status: :failed)
      end
      
      Rails.logger.info "[STRIPE SUBSCRIPTION] Synced subscription #{customer_subscription.id} with Stripe"
      true
    rescue => e
      Rails.logger.error "[STRIPE SUBSCRIPTION] Error syncing subscription #{customer_subscription.id}: #{e.message}"
      false
    end
  end
  
  def handle_stripe_webhook(event)
    case event.type
    when 'customer.subscription.created'
      handle_subscription_created(event.data.object)
    when 'customer.subscription.updated'
      handle_subscription_updated(event.data.object)
    when 'customer.subscription.deleted'
      handle_subscription_deleted(event.data.object)
    when 'invoice.payment_succeeded'
      handle_payment_succeeded(event.data.object)
    when 'invoice.payment_failed'
      handle_payment_failed(event.data.object)
    else
      Rails.logger.info "[STRIPE WEBHOOK] Unhandled event type: #{event.type}"
    end
  end
  
  private
  
  def ensure_stripe_customer
    # Check if tenant_customer already has a Stripe customer ID
    if tenant_customer.stripe_customer_id.present?
      begin
        return Stripe::Customer.retrieve(tenant_customer.stripe_customer_id, {
          stripe_account: business.stripe_account_id
        })
      rescue Stripe::InvalidRequestError
        # Stripe customer doesn't exist, create a new one
        Rails.logger.warn "[STRIPE] Stripe customer #{tenant_customer.stripe_customer_id} not found, creating new one"
      end
    end
    
    # Create new Stripe customer
    create_stripe_customer
  end
  
  def create_stripe_customer
    begin
      stripe_customer = Stripe::Customer.create({
        email: tenant_customer.email,
        name: tenant_customer.full_name,
        metadata: {
          tenant_customer_id: tenant_customer.id,
          business_id: business.id
        }
      }, {
        stripe_account: business.stripe_account_id
      })
      
      # Update tenant_customer with Stripe ID
      tenant_customer.update!(stripe_customer_id: stripe_customer.id)
      
      Rails.logger.info "[STRIPE] Created Stripe customer #{stripe_customer.id} for tenant customer #{tenant_customer.id}"
      stripe_customer
    rescue => e
      Rails.logger.error "[STRIPE] Error creating Stripe customer for tenant customer #{tenant_customer.id}: #{e.message}"
      nil
    end
  end
  
  def create_stripe_subscription_object(stripe_customer)
    begin
      Stripe::Subscription.create({
        customer: stripe_customer.id,
        items: [{
          price: get_stripe_price_id,
          quantity: customer_subscription.quantity || 1
        }],
        application_fee_percent: get_application_fee_percent,
        metadata: {
          customer_subscription_id: customer_subscription.id,
          business_id: business.id,
          tenant_customer_id: tenant_customer.id
        },
        expand: ['latest_invoice.payment_intent']
      }, {
        stripe_account: business.stripe_account_id
      })
    rescue => e
      Rails.logger.error "[STRIPE] Error creating Stripe subscription: #{e.message}"
      nil
    end
  end
  
  def get_stripe_price_id
    # Try to get Stripe price ID from service or subscription
    if customer_subscription.service.respond_to?(:stripe_price_id) && customer_subscription.service.stripe_price_id.present?
      return customer_subscription.service.stripe_price_id
    end
    
    # Fallback: create a price on the fly (not recommended for production)
    create_stripe_price
  end
  
  def create_stripe_price
    begin
      price = Stripe::Price.create({
        unit_amount: (customer_subscription.subscription_price * 100).to_i, # Convert to cents
        currency: 'usd',
        recurring: {
          interval: stripe_interval
        },
        product_data: {
          name: customer_subscription.service.name,
          metadata: {
            service_id: customer_subscription.service.id,
            business_id: business.id
          }
        }
      }, {
        stripe_account: business.stripe_account_id
      })
      
      Rails.logger.info "[STRIPE] Created price #{price.id} for service #{customer_subscription.service.id}"
      price.id
    rescue => e
      Rails.logger.error "[STRIPE] Error creating Stripe price: #{e.message}"
      nil
    end
  end
  
  def stripe_interval
    case customer_subscription.frequency
    when 'weekly'
      'week'
    when 'biweekly'
      'week' # Stripe doesn't support biweekly, handle with interval_count
    when 'monthly'
      'month'
    when 'quarterly'
      'month' # Handle with interval_count of 3
    when 'annually'
      'year'
    else
      'month'
    end
  end
  
  def handle_subscription_created(stripe_subscription)
    subscription = find_subscription_by_stripe_id(stripe_subscription.id)
    return unless subscription
    
    # Update status based on Stripe status
    case stripe_subscription.status
    when 'active'
      subscription.update!(status: :active) unless subscription.active?
    when 'canceled', 'cancelled'
      subscription.update!(status: :cancelled, cancelled_at: Time.current)
    end
    
    Rails.logger.info "[STRIPE WEBHOOK] Subscription created: #{stripe_subscription.id}"
  end
  
  def handle_subscription_updated(stripe_subscription)
    subscription = find_subscription_by_stripe_id(stripe_subscription.id)
    return unless subscription
    
    # Update status based on Stripe status
    case stripe_subscription.status
    when 'active'
      subscription.update!(status: :active) unless subscription.active?
    when 'canceled', 'cancelled'
      subscription.update!(status: :cancelled, cancelled_at: Time.current)
    when 'past_due', 'unpaid'
      subscription.update!(status: :failed)
    end
    
    Rails.logger.info "[STRIPE WEBHOOK] Subscription updated: #{stripe_subscription.id}"
  end
  
  def handle_subscription_deleted(stripe_subscription)
    subscription = find_subscription_by_stripe_id(stripe_subscription.id)
    return unless subscription
    
    subscription.update!(
      status: :cancelled,
      cancelled_at: Time.current
    )
    
    Rails.logger.info "[STRIPE WEBHOOK] Subscription deleted: #{stripe_subscription.id}"
  end
  
  def handle_payment_succeeded(invoice)
    subscription = find_subscription_by_stripe_subscription_id(invoice.subscription)
    return unless subscription
    
    # Create payment record
    create_payment_record(subscription, invoice, 'succeeded')
    
    # Award loyalty points for successful payment
    if subscription.business.loyalty_program_enabled? && defined?(SubscriptionLoyaltyService)
      loyalty_service = SubscriptionLoyaltyService.new(subscription)
      loyalty_service.award_subscription_payment_points!
    end
    
    Rails.logger.info "[STRIPE WEBHOOK] Payment succeeded for subscription: #{subscription.id}"
  end
  
  def handle_payment_failed(invoice)
    subscription = find_subscription_by_stripe_subscription_id(invoice.subscription)
    return unless subscription
    
    # Create payment record
    create_payment_record(subscription, invoice, 'failed')
    
    # Update subscription status
    subscription.update!(status: :failed)
    
    Rails.logger.warn "[STRIPE WEBHOOK] Payment failed for subscription: #{subscription.id}"
  end
  
  def find_subscription_by_stripe_id(stripe_subscription_id)
    CustomerSubscription.find_by(stripe_subscription_id: stripe_subscription_id)
  end
  
  def find_subscription_by_stripe_subscription_id(stripe_subscription_id)
    CustomerSubscription.find_by(stripe_subscription_id: stripe_subscription_id)
  end
  
  def create_payment_record(subscription, invoice, status)
    # Create a payment/transaction record if you have such a model
    if defined?(Transaction)
      Transaction.create!(
        tenant_customer: subscription.tenant_customer,
        business: subscription.business,
        amount: invoice.amount_paid / 100.0, # Convert from cents
        transaction_type: 'subscription_payment',
        status: status,
        stripe_invoice_id: invoice.id,
        description: "Subscription payment for #{subscription.service.name}"
      )
    end
  end

  # Get application fee percentage for Stripe subscriptions.
  # Uses the per-business platform fee.
  def get_application_fee_percent
    business.platform_fee_percentage
  end
end 
 
 
 