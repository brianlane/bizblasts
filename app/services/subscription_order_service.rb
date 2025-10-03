# frozen_string_literal: true

class SubscriptionOrderService
  attr_reader :customer_subscription, :business, :tenant_customer, :product
  
  def initialize(customer_subscription)
    @customer_subscription = customer_subscription
    @business = customer_subscription.business
    @tenant_customer = customer_subscription.tenant_customer
    @product = customer_subscription.product
  end
  
  def process_subscription!
    return false unless customer_subscription.product_subscription?
    return false unless customer_subscription.active?
    
    # Use the enhanced stock service for intelligent order processing
    stock_service = SubscriptionStockService.new(customer_subscription)
    result = stock_service.process_subscription_with_stock_intelligence!
    
    if result
      Rails.logger.info "[SUBSCRIPTION ORDER] Successfully processed subscription #{customer_subscription.id} with enhanced stock management"
      result
    else
      Rails.logger.warn "[SUBSCRIPTION ORDER] Enhanced stock management failed, falling back to basic order logic"
      fallback_to_basic_order
    end
  rescue => e
    Rails.logger.error "[SUB_ORDER] Error processing subscription #{customer_subscription.id}: #{e.message}"
    false
  end
  
  private
  
  def fallback_to_basic_order
    ActiveRecord::Base.transaction do
      # Create order for the subscription
      order = create_subscription_order
      return false unless order
      
      # Create invoice for the order
      invoice = create_order_invoice(order)
      
      # Award loyalty points for subscription payment
      award_subscription_loyalty_points!
      
      # Check for subscription milestones and award bonus points
      check_and_award_milestone_points!
      
      # Send notifications
      send_order_notifications(order)
      
      # Update subscription billing date
      customer_subscription.advance_billing_date!
      
      Rails.logger.info "[SUB_ORDER] Successfully created order #{order.id} for subscription #{customer_subscription.id}"
      
      order
    end
  end
  
  def create_subscription_order
    # Handle out-of-stock scenario
    if !product_in_stock?
      handle_out_of_stock_scenario
      return nil
    end

    order = business.orders.create!(
      tenant_customer: tenant_customer,
      order_number: generate_order_number,
      status: 'paid',
      order_type: 'product',
      total_amount: customer_subscription.subscription_price,
      notes: "Subscription order for #{product.name}"
    )

    # Create line item for the product
    create_order_line_item(order)
    
    # Reload order to ensure total_amount is current after line item creation
    order.reload
    
    order
  end
  
  def product_in_stock?
    return true unless product.respond_to?(:stock_quantity)
    product.stock_quantity >= customer_subscription.quantity
  end
  
  def handle_out_of_stock_scenario
    case customer_subscription.customer_out_of_stock_preference || customer_subscription.out_of_stock_action
    when 'skip_delivery'
      handle_skip_delivery_scenario
    when 'loyalty_points'
      handle_loyalty_points_scenario
    when 'contact_customer'
      handle_contact_customer_scenario
    else
      handle_skip_delivery_scenario # Default fallback
    end
  end
  
  def handle_skip_delivery_scenario
    Rails.logger.info "[SUB_ORDER] Skipping delivery for subscription #{customer_subscription.id} due to out of stock"
    customer_subscription.advance_billing_date!
  end
  
  def handle_loyalty_points_scenario
    Rails.logger.info "[SUB_ORDER] Handling subscription #{customer_subscription.id} due to out of stock with loyalty points scenario"
    # TODO: Implement loyalty points scenario
    handle_skip_delivery_scenario # Fallback to skip for now
  end
  
  def handle_contact_customer_scenario
    Rails.logger.info "[SUB_ORDER] Contacting customer for subscription #{customer_subscription.id} due to out of stock"
    # TODO: Send out of stock notification email
    handle_skip_delivery_scenario # Fallback to skip for now
  end
  
  def generate_order_number
    tz = business.time_zone.presence || 'UTC'
    now = Time.current.in_time_zone(tz)
    "SUB-#{now.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
  end
  
  def create_order_line_item(order)
    variant = determine_product_variant
    
    # If no variant exists, create a default one
    if variant.nil?
      variant = product.product_variants.create!(
        name: "Default",
        price_modifier: 0.0,
        stock_quantity: product.stock_quantity || 0
      )
    end
    
    # Use subscription price per unit to account for any subscription discounts
    unit_price = customer_subscription.subscription_price / customer_subscription.quantity
    
    order.line_items.create!(
      product_variant: variant,
      quantity: customer_subscription.quantity,
      price: unit_price,
      total_amount: customer_subscription.subscription_price
    )
  end
  
  def calculate_variant_price(variant)
    base_price = product.price
    modifier = variant.price_modifier || 0
    base_price + modifier
  end
  
  def determine_product_variant
    # Use customer's preferred variant if specified via product_variant association
    if customer_subscription.product_variant_id.present?
      variant = product.product_variants.find_by(id: customer_subscription.product_variant_id)
      return variant if variant
    end

    # Fall back to default variant or first available variant
    product.product_variants.first
  end
  
  def create_order_invoice(order)
    tz = business.time_zone.presence || 'UTC'
    local_today = Time.current.in_time_zone(tz).to_date
    invoice = order.build_invoice(
      tenant_customer: tenant_customer,
      business: business,
      amount: order.total_amount,
      total_amount: order.total_amount,
      due_date: local_today + 30.days,
      status: 'paid' # Subscription orders are pre-paid
    )
    
    invoice.save!
    invoice
  end
  
  def send_order_notifications(order)
    # Send customer notification
    begin
      NotificationService.subscription_order_created(order)
      Rails.logger.info "[NOTIFICATION] Sent subscription order notification (email + SMS) to customer for order #{order.id}"
    rescue => e
      Rails.logger.error "[NOTIFICATION] Failed to send customer notification for order #{order.id}: #{e.message}"
    end

    # Send business notification
    begin
      BusinessMailer.subscription_order_received(order).deliver_later
      Rails.logger.info "[EMAIL] Sent subscription order notification to business for order #{order.id}"
    rescue => e
      Rails.logger.error "[EMAIL] Failed to send business notification for order #{order.id}: #{e.message}"
    end
  end

  def award_subscription_loyalty_points!
    return unless business.loyalty_program_enabled?
    
    loyalty_service = SubscriptionLoyaltyService.new(customer_subscription)
    loyalty_service.award_subscription_payment_points!
    
    Rails.logger.info "[SUBSCRIPTION LOYALTY] Awarded points for subscription #{customer_subscription.id}"
  end

  def check_and_award_milestone_points!
    return unless business.loyalty_program_enabled?
    
    loyalty_service = SubscriptionLoyaltyService.new(customer_subscription)
    
    # Calculate number of full calendar months since subscription start
    tz = business.time_zone.presence || 'UTC'
    local_start_date = customer_subscription.created_at.in_time_zone(tz).to_date
    local_current_date = Time.current.in_time_zone(tz).to_date
    raw_months = (local_current_date.year * 12 + local_current_date.month) -
                 (local_start_date.year * 12 + local_start_date.month)
    anniversary_date = local_start_date >> raw_months
    subscription_months = raw_months - (local_current_date < anniversary_date ? 1 : 0)

    case subscription_months
    when 1
      loyalty_service.award_milestone_points!('first_month') unless milestone_awarded?('first_month')
    when 3
      loyalty_service.award_milestone_points!('three_months') unless milestone_awarded?('three_months')
    when 6
      loyalty_service.award_milestone_points!('six_months') unless milestone_awarded?('six_months')
    when 12
      loyalty_service.award_milestone_points!('one_year') unless milestone_awarded?('one_year')
    when 24
      loyalty_service.award_milestone_points!('two_years') unless milestone_awarded?('two_years')
    end
    
    Rails.logger.info "[SUBSCRIPTION LOYALTY] Checked milestones for subscription #{customer_subscription.id}"
  end

  def milestone_awarded?(milestone_type)
    description_pattern = case milestone_type
                         when 'first_month' then '%First month subscription milestone%'
                         when 'three_months' then '%Three month subscription milestone%'
                         when 'six_months' then '%Six month subscription milestone%'
                         when 'one_year' then '%One year subscription milestone%'
                         when 'two_years' then '%Two year subscription milestone%'
                         end

    tenant_customer.loyalty_transactions
                   .where('description LIKE ?', description_pattern)
                   .exists?
  end
end 
 
 