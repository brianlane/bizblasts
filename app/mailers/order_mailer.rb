class OrderMailer < ApplicationMailer
  # Send order confirmation email (receipt) when payment is completed
  def order_confirmation(order)
    @order = order
    @business = order.business
    @customer = order.tenant_customer
    @invoice = order.invoice
    @payment = @invoice&.payments&.successful&.last
    
    # Add tier-specific features for premium businesses
    @include_analytics = @business.tier == 'premium'
    
    mail(
      to: @customer.email,
      subject: "Order Confirmation ##{@order.order_number} - #{@business.name}",
      reply_to: @business.email
    )
  end
  
  # Send order status update emails (standard+ tier only)
  def order_status_update(order, previous_status)
    return unless order.business.tier.in?(['standard', 'premium'])
    
    @order = order
    @business = order.business
    @customer = order.tenant_customer
    @previous_status = previous_status
    @current_status = order.status
    
    # Add tier-specific features for premium businesses
    @include_analytics = @business.tier == 'premium'
    
    subject_text = case @current_status
                   when 'shipped' then "Your Order Has Shipped"
                   when 'processing' then "Your Order Is Being Processed"
                   when 'cancelled' then "Order Cancelled"
                   when 'refunded' then "Order Refunded"
                   else "Order Status Update"
                   end
    
    mail(
      to: @customer.email,
      subject: "#{subject_text} - Order ##{@order.order_number} - #{@business.name}",
      reply_to: @business.email
    )
  end
  
  # Send refund confirmation (standard+ tier only)
  def refund_confirmation(order, payment)
    return unless order.business.tier.in?(['standard', 'premium'])
    
    @order = order
    @business = order.business
    @customer = order.tenant_customer
    @payment = payment
    @refund_amount = payment.refunded_amount || payment.amount
    
    # Add tier-specific features for premium businesses
    @include_analytics = @business.tier == 'premium'
    
    mail(
      to: @customer.email,
      subject: "Refund Processed - Order ##{@order.order_number} - #{@business.name}",
      reply_to: @business.email
    )
  end

  # Send subscription order confirmation email to customer
  def subscription_order_created(order)
    @order = order
    @business = order.business
    @customer = order.tenant_customer
    @subscription = order.customer_subscription
    
    mail(
      to: @customer.email,
      subject: "Subscription Order Created - #{@business.name}",
      from: @business.email,
      reply_to: @business.email
    )
  end
end 