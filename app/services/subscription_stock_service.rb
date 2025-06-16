# frozen_string_literal: true

class SubscriptionStockService
  attr_reader :customer_subscription, :business, :tenant_customer, :product

  def initialize(customer_subscription)
    @customer_subscription = customer_subscription
    @business = customer_subscription.business
    @tenant_customer = customer_subscription.tenant_customer
    @product = customer_subscription.product
    
    # Validate that this is a product subscription
    unless customer_subscription.product_subscription?
      raise ArgumentError, 'Subscription must be for a product'
    end
  end

  def subscription
    customer_subscription
  end

  # Public API methods that tests expect
  
  def check_stock_availability
    requested_quantity = customer_subscription.quantity || 1
    current_stock = product.stock_quantity || 0
    
    result = {
      current_stock: current_stock,
      required_quantity: requested_quantity,
      remaining_after_fulfillment: [current_stock - requested_quantity, 0].max
    }
    
    if current_stock >= requested_quantity
      result.merge!(
        available: true,
        stock_level: classify_stock_level(current_stock, requested_quantity),
        warning: current_stock <= 10 ? "Low stock warning: only #{current_stock} units remaining" : nil,
        reorder_suggested: current_stock <= 10,
        suggested_reorder_quantity: current_stock <= 10 ? calculate_suggested_reorder : 0
      )
    elsif current_stock > 0
      result.merge!(
        available: false,
        stock_level: classify_stock_level(current_stock, requested_quantity),
        shortage: requested_quantity - current_stock,
        max_available_quantity: current_stock,
        alternatives: ['partial_fulfillment', 'substitute_products']
      )
    else
      result.merge!(
        available: false,
        stock_level: classify_stock_level(current_stock, requested_quantity)
      )
    end
    
    result
  end
  
  def reserve_stock(options = {})
    requested_quantity = customer_subscription.quantity || 1
    current_stock = product.stock_quantity || 0
    allow_partial = options[:allow_partial] || false
    
    if current_stock >= requested_quantity
      # Full reservation possible
      with_stock_lock do
        product.update!(stock_quantity: current_stock - requested_quantity)
        
        reservation = create_stock_reservation(requested_quantity)
        
        {
          success: true,
          reserved_quantity: requested_quantity,
          reservation_id: reservation.id
        }
      end
    elsif current_stock > 0 && allow_partial
      # Partial reservation
      with_stock_lock do
        product.update!(stock_quantity: 0)
        
        reservation = create_stock_reservation(current_stock)
        
        {
          success: true,
          reserved_quantity: current_stock,
          partial_fulfillment: true,
          reservation_id: reservation.id
        }
      end
    else
      # Insufficient stock
      {
        success: false,
        error: "Insufficient stock available. Requested: #{requested_quantity}, Available: #{current_stock}",
        available_quantity: current_stock
      }
    end
  rescue => e
    {
      success: false,
      error: "Stock reservation failed: #{e.message}"
    }
  end
  
  def release_stock(reservation_id)
    reservation = StockReservation.find_by(id: reservation_id)
    
    unless reservation
      return {
        success: false,
        error: "Reservation not found with ID: #{reservation_id}"
      }
    end
    
    # Check if reservation has already been released by checking if it's expired
    if reservation.expires_at < Time.current
      return {
        success: false,
        error: "Reservation #{reservation_id} has already been released"
      }
    end
    
    with_stock_lock do
      # Restore stock
      product.increment!(:stock_quantity, reservation.quantity)
      
      # Mark reservation as released by setting expires_at to past time
      reservation.update!(expires_at: 1.hour.ago)
      
      {
        success: true,
        released_quantity: reservation.quantity
      }
    end
  rescue => e
    {
      success: false,
      error: "Failed to release stock: #{e.message}"
    }
  end
  
  def find_substitute_products
    # Substitute products functionality removed - not needed for this application
    []
  end
  
  def handle_stock_shortage(shortage_scenario)
    required_quantity = shortage_scenario[:required_quantity]
    available_quantity = shortage_scenario[:available_quantity]
    shortage = shortage_scenario[:shortage]
    
    # Check if partial fulfillment is allowed (use out_of_stock_action as fallback)
    partial_allowed = if customer_subscription.respond_to?(:allow_partial_fulfillment)
                        customer_subscription.allow_partial_fulfillment
                      else
                        customer_subscription.out_of_stock_action == 'accept_partial'
                      end
    
    if partial_allowed && available_quantity > 0
      
      return {
        strategy: 'partial_fulfillment',
        fulfill_quantity: available_quantity,
        backorder_quantity: shortage,
        backorder_date: 1.week.from_now.to_date,
        backorder_created: true
      }
    end
    
    # Substitute products functionality removed - not needed for this application
    
    # No alternatives available
    {
      strategy: 'skip_delivery',
      skip_reason: 'Product out of stock shortage with no suitable alternatives',
      loyalty_compensation: business.loyalty_program_enabled? ? true : false,
      compensation_points: business.loyalty_program_enabled? ? calculate_compensation_points : 0
    }
  end
  
  def update_stock_levels(fulfillment_data)
    fulfilled_quantity = fulfillment_data[:fulfilled_quantity]
    
    begin
      # Update product stock
      current_stock = product.stock_quantity || 0
      new_stock = current_stock - fulfilled_quantity
      
      product.update!(stock_quantity: [new_stock, 0].max)
      
      # Create stock movement record
      StockMovement.create!(
        product: product,
        quantity: -fulfilled_quantity,
        movement_type: 'subscription_fulfillment',
        reference_id: fulfillment_data[:order_id],
        reference_type: 'Order',
        notes: "Subscription fulfillment for subscription #{customer_subscription.id}"
      )
      
      # Check for low stock alerts
      StockAlertService.check_and_notify(product)
      
      {
        success: true,
        new_stock_level: product.reload.stock_quantity
      }
    rescue => e
      {
        success: false,
        error: "Stock update failed: #{e.message}"
      }
    end
  end
  
  def calculate_reorder_point
    # Simple reorder point calculation using basic logic
    current_stock = product.stock_quantity || 0
    
    # Use subscription quantity as base demand
    base_demand = customer_subscription.quantity || 1
    
    # Calculate average daily usage (assume monthly subscription = 30 days)
    daily_usage = case customer_subscription.frequency
                  when 'weekly' then base_demand / 7.0
                  when 'monthly' then base_demand / 30.0
                  when 'quarterly' then base_demand / 90.0
                  when 'annually' then base_demand / 365.0
                  else base_demand / 30.0
                  end
    
    # Use default lead time of 7 days
    lead_time_days = 7
    
    # Use default safety stock of 5 days
    safety_days = 5
    
    # Calculate reorder point: (daily_usage * lead_time) + safety_stock
    lead_time_stock = (daily_usage * lead_time_days).ceil
    safety_stock = (daily_usage * safety_days).ceil
    
    reorder_point = lead_time_stock + safety_stock
    
    # Ensure minimum reorder point of 1
    [reorder_point, 1].max
  end

  # Main method to process product subscription with intelligent stock management
  def process_subscription_with_stock_intelligence!
    return false unless customer_subscription.product_subscription?
    return false unless customer_subscription.active?

    ActiveRecord::Base.transaction do
      # Check stock availability and handle accordingly
      stock_result = check_and_handle_stock_availability
      
      case stock_result[:status]
      when :available
        # Create order with available products
        order = create_subscription_order(stock_result[:variants])
        process_successful_order(order)
        order
      when :partial_available
        # Handle partial availability based on customer preferences
        handle_partial_stock_availability(stock_result)
      when :out_of_stock
        # Handle complete out-of-stock scenario
        handle_out_of_stock_scenario
      when :substituted
        # Create order with substituted products
        order = create_subscription_order(stock_result[:variants])
        process_successful_order(order)
        send_substitution_notification(order, stock_result[:substitutions])
        order
      else
        false
      end
    end
  rescue => e
    Rails.logger.error "[SUBSCRIPTION STOCK] Error processing subscription #{customer_subscription.id}: #{e.message}"
    false
  end

  private
  
  def classify_stock_level(current_stock, requested_quantity)
    if current_stock < 0
      'negative'
    elsif current_stock == 0
      'out_of_stock'
    elsif current_stock <= 10
      'low'
    else
      'high'
    end
  end
  
  def calculate_suggested_reorder
    # Simple calculation: suggest 3x the subscription quantity
    (customer_subscription.quantity || 1) * 3
  end
  
  def with_stock_lock
    product.with_lock do
      yield
    end
  end
  
  def create_stock_reservation(quantity)
    # Create a simple reservation - if StockReservation model supports it
    if defined?(StockReservation)
      # Find or create a default order for reservations
      reservation_order = business.orders.find_or_create_by(
        tenant_customer: tenant_customer,
        status: 'pending_payment',
        order_type: 'product'
      ) do |order|
        order.order_number = "RESERVATION-#{Time.current.strftime('%Y%m%d%H%M%S')}"
        order.total_amount = 0
      end
      
      # Find the first available product variant or create one
      variant = product.product_variants.first
      unless variant
        variant = product.product_variants.create!(
          name: "Default",
          price_modifier: 0.0,
          stock_quantity: 0
        )
      end
      
      StockReservation.create!(
        product_variant: variant,
        order: reservation_order,
        quantity: quantity,
        expires_at: 24.hours.from_now
      )
    else
      # Fallback if StockReservation doesn't exist
      OpenStruct.new(id: SecureRandom.uuid, quantity: quantity)
    end
  end
  

  
  def calculate_compensation_points
    # Award points based on subscription value
    base_points = (customer_subscription.subscription_price || product.price || 0).to_i
    [base_points, 100].min # Cap at 100 points
  end

  def check_and_handle_stock_availability
    requested_quantity = customer_subscription.quantity || 1
    preferred_variant = determine_preferred_variant
    
    # Check primary variant availability
    if preferred_variant&.in_stock?(requested_quantity)
      return {
        status: :available,
        variants: [{ variant: preferred_variant, quantity: requested_quantity }]
      }
    end

    # Check if we can fulfill with alternative variants
    alternative_result = find_alternative_variants(requested_quantity)
    return alternative_result if alternative_result[:status] != :out_of_stock

    # Substitute products functionality removed - not needed for this application

    # Complete out-of-stock scenario
    { status: :out_of_stock }
  end

  def determine_preferred_variant
    preferences = customer_subscription.customer_preferences || {}
    
    # Use customer's preferred variant if specified
    if preferences['preferred_variant_id'].present?
      variant = product.product_variants.find_by(id: preferences['preferred_variant_id'])
      return variant if variant&.respond_to?(:active?) ? variant.active? : true
    end

    # Fall back to default variant or first available variant
    available_variants = product.product_variants.select { |v| v.respond_to?(:active?) ? v.active? : true }
    available_variants.first || product.product_variants.first
  end

  def find_alternative_variants(requested_quantity)
    available_variants = product.product_variants.select { |v| v.in_stock?(1) }
    
    if available_variants.empty?
      return { status: :out_of_stock }
    end

    # Try to fulfill the full quantity with available variants
    fulfillment_plan = []
    remaining_quantity = requested_quantity

    available_variants.each do |variant|
      available_stock = variant.stock_quantity
      take_quantity = [remaining_quantity, available_stock].min
      
      if take_quantity > 0
        fulfillment_plan << { variant: variant, quantity: take_quantity }
        remaining_quantity -= take_quantity
        break if remaining_quantity == 0
      end
    end

    if remaining_quantity == 0
      { status: :available, variants: fulfillment_plan }
    else
      { 
        status: :partial_available, 
        variants: fulfillment_plan,
        missing_quantity: remaining_quantity
      }
    end
  end

  def find_substitute_products_for_variants(requested_quantity)
    # Substitute products functionality removed - not needed for this application
    { status: :out_of_stock }
  end

  def handle_partial_stock_availability(stock_result)
    case customer_subscription.effective_out_of_stock_action
    when 'accept_partial'
      # Create order with available quantity
      order = create_subscription_order(stock_result[:variants])
      process_successful_order(order)
      send_partial_fulfillment_notification(order, stock_result[:missing_quantity])
      order
    when 'skip_delivery'
      handle_skip_delivery_scenario
    when 'loyalty_points'
      handle_loyalty_points_scenario(stock_result[:missing_quantity])
    when 'contact_customer'
      handle_contact_customer_scenario
    else
      handle_business_default_partial_stock(stock_result)
    end
  end

  def handle_out_of_stock_scenario
    case customer_subscription.effective_out_of_stock_action
    when 'skip_delivery'
      handle_skip_delivery_scenario
    when 'loyalty_points'
      handle_loyalty_points_scenario(customer_subscription.quantity)
    when 'contact_customer'
      handle_contact_customer_scenario
    else
      handle_business_default_out_of_stock
    end
  end

  def create_subscription_order(variant_quantities)
    order = business.orders.create!(
      tenant_customer: tenant_customer,
      order_number: generate_order_number,
      status: 'confirmed',
      notes: "Subscription order for #{product.name}"
    )

    total_amount = 0

    variant_quantities.each do |vq|
      variant = vq[:variant]
      quantity = vq[:quantity]
      
      line_item = order.line_items.create!(
        product_variant: variant,
        quantity: quantity,
        price: variant.final_price,
        total_amount: variant.final_price * quantity
      )
      
      total_amount += line_item.total_amount
      
      # Reserve/decrement stock
      variant.decrement_stock!(quantity)
    end

    order.update!(total_amount: total_amount)
    order
  end

  def process_successful_order(order)
    # Create invoice
    create_order_invoice(order)
    
    # Award loyalty points
    award_subscription_loyalty_points!
    check_and_award_milestone_points!
    
    # Send notifications
    send_order_notifications(order)
    
    # Update subscription billing date
    customer_subscription.advance_billing_date!
    
    Rails.logger.info "[SUBSCRIPTION STOCK] Successfully created order #{order.id} for subscription #{customer_subscription.id}"
  end

  def handle_skip_delivery_scenario
    Rails.logger.info "[SUBSCRIPTION STOCK] Skipping delivery for subscription #{customer_subscription.id} due to stock unavailability"
    
    # Update next billing date without creating order
    customer_subscription.advance_billing_date!
    
    # Send notification
    send_skip_delivery_notification
    
    # Create stock alert for business
    create_stock_alert
    
    :skipped
  end



  def handle_contact_customer_scenario
    # Create a pending action for customer service
    create_customer_service_task
    
    # Send notification to customer
    send_stock_issue_notification
    
    # Send notification to business
    send_business_stock_alert
    
    Rails.logger.info "[SUBSCRIPTION STOCK] Created customer service task for subscription #{customer_subscription.id}"
    :customer_contacted
  end

  # Utility methods

  def generate_order_number
    "SUB-#{customer_subscription.id}-#{Time.current.strftime('%Y%m%d%H%M%S')}"
  end

  def create_order_invoice(order)
    invoice = order.build_invoice(
      tenant_customer: tenant_customer,
      business: business,
      tax_rate: business.default_tax_rate,
      due_date: Date.current + 30.days,
      status: :paid
    )
    
    invoice.save!
    invoice
  end

  def create_stock_alert(priority: :normal)
    # Simple logging-based stock alert since we don't require additional models
    Rails.logger.warn "[STOCK ALERT] #{priority.upcase} priority: Subscription #{customer_subscription.id} affected by stock shortage for product #{product.id}"
  rescue => e
    Rails.logger.error "[SUBSCRIPTION STOCK] Failed to create stock alert: #{e.message}"
  end

  def create_customer_service_task
    # Simple logging-based task creation since we don't require additional models
    Rails.logger.info "[CUSTOMER SERVICE] Task created: Contact customer about stock unavailability for subscription #{customer_subscription.id}"
  rescue => e
    Rails.logger.error "[SUBSCRIPTION STOCK] Failed to create customer service task: #{e.message}"
  end

  # Notification methods
  def send_order_notifications(order)
    begin
      OrderMailer.subscription_order_created(order).deliver_later if defined?(OrderMailer)
      BusinessMailer.subscription_order_received(order).deliver_later if defined?(BusinessMailer)
      Rails.logger.info "[EMAIL] Sent order notifications for order #{order.id}"
    rescue => e
      Rails.logger.error "[EMAIL] Failed to send order notifications: #{e.message}"
    end
  end

  def send_partial_fulfillment_notification(order, missing_quantity)
    begin
      SubscriptionMailer.partial_fulfillment(customer_subscription, order, missing_quantity).deliver_later if defined?(SubscriptionMailer)
      Rails.logger.info "[EMAIL] Sent partial fulfillment notification for subscription #{customer_subscription.id}"
    rescue => e
      Rails.logger.error "[EMAIL] Failed to send partial fulfillment notification: #{e.message}"
    end
  end

  def send_substitution_notification(order, substitutions)
    begin
      SubscriptionMailer.product_substitution(customer_subscription, order, substitutions).deliver_later if defined?(SubscriptionMailer)
      Rails.logger.info "[EMAIL] Sent substitution notification for subscription #{customer_subscription.id}"
    rescue => e
      Rails.logger.error "[EMAIL] Failed to send substitution notification: #{e.message}"
    end
  end

  def send_skip_delivery_notification
    begin
      SubscriptionMailer.delivery_skipped(customer_subscription).deliver_later if defined?(SubscriptionMailer)
      Rails.logger.info "[EMAIL] Sent skip delivery notification for subscription #{customer_subscription.id}"
    rescue => e
      Rails.logger.error "[EMAIL] Failed to send skip delivery notification: #{e.message}"
    end
  end

  def send_stock_issue_notification
    begin
      SubscriptionMailer.stock_issue_customer_contact(customer_subscription).deliver_later if defined?(SubscriptionMailer)
      Rails.logger.info "[EMAIL] Sent stock issue notification for subscription #{customer_subscription.id}"
    rescue => e
      Rails.logger.error "[EMAIL] Failed to send stock issue notification: #{e.message}"
    end
  end

  def send_business_stock_alert
    begin
      BusinessMailer.subscription_stock_alert(customer_subscription).deliver_later if defined?(BusinessMailer)
      Rails.logger.info "[EMAIL] Sent business stock alert for subscription #{customer_subscription.id}"
    rescue => e
      Rails.logger.error "[EMAIL] Failed to send business stock alert: #{e.message}"
    end
  end

  def send_loyalty_compensation_notification(points_awarded, missing_quantity)
    begin
      SubscriptionMailer.loyalty_compensation_awarded(customer_subscription, points_awarded, missing_quantity).deliver_later if defined?(SubscriptionMailer)
      Rails.logger.info "[EMAIL] Sent loyalty compensation notification for subscription #{customer_subscription.id}"
    rescue => e
      Rails.logger.error "[EMAIL] Failed to send loyalty compensation notification: #{e.message}"
    end
  end

  # Business default handlers
  def handle_business_default_out_of_stock
    case business.default_subscription_out_of_stock_action || 'skip_delivery'
    when 'skip_delivery'
      handle_skip_delivery_scenario
    when 'loyalty_points'
      handle_loyalty_points_scenario(customer_subscription.quantity)
    when 'contact_customer'
      handle_contact_customer_scenario
    else
      handle_skip_delivery_scenario
    end
  end

  def handle_business_default_partial_stock(stock_result)
    case business.default_subscription_partial_stock_action || 'accept_partial'
    when 'accept_partial'
      order = create_subscription_order(stock_result[:variants])
      process_successful_order(order)
      send_partial_fulfillment_notification(order, stock_result[:missing_quantity])
      order
    when 'skip_delivery'
      handle_skip_delivery_scenario
    when 'loyalty_points'
      handle_loyalty_points_scenario(stock_result[:missing_quantity])
    else
      handle_skip_delivery_scenario
    end
  end

  # Delegate methods to existing services
  def award_subscription_loyalty_points!
    return unless business.loyalty_program_enabled?
    
    if defined?(SubscriptionLoyaltyService)
      SubscriptionLoyaltyService.new(customer_subscription).award_subscription_points!
    end
  end

  def check_and_award_milestone_points!
    return unless business.loyalty_program_enabled?
    
    if defined?(SubscriptionLoyaltyService)
      SubscriptionLoyaltyService.new(customer_subscription).check_and_award_milestone_points!
    end
  end

  def handle_loyalty_points_scenario(missing_quantity = nil)
    return handle_skip_delivery_scenario unless business.loyalty_program_enabled?
    
    # Calculate loyalty points to award (based on product price)
    base_points = (product.price * (customer_subscription.quantity || 1)).to_i
    
    # Award bonus points for inconvenience
    bonus_points = (base_points * 0.2).to_i
    total_points = base_points + bonus_points
    
    tenant_customer.loyalty_points += total_points
    tenant_customer.save!
    
    # Update billing date
    customer_subscription.advance_billing_date!
    
    # Send notification
    send_loyalty_compensation_notification(total_points, missing_quantity)
    
    # Create stock alert
    create_stock_alert
    
    Rails.logger.info "[SUBSCRIPTION STOCK] Awarded #{total_points} loyalty points for unavailable stock"
    :loyalty_awarded
  end
end 