class BusinessMailer < ApplicationMailer
  # Send domain request notification to premium business users after email confirmation
  def domain_request_notification(user)
    @user = user
    @business = user.business
    @domain_requested = @business.hostname if @business.host_type_custom_domain?
    
    mail(
      to: @user.email,
      subject: "Custom Domain Request Received - #{@business.name}"
    )
  end

  # Send notification to business when a new booking is made
  def new_booking_notification(booking)
    @booking = booking
    @business = booking.business
    @customer = booking.tenant_customer
    @service = booking.service
    @staff_member = booking.staff_member
    
    # Check if business user has this notification enabled
    business_user = @business.users.where(role: [:manager, :owner]).first
    return unless business_user&.notification_preferences&.fetch('email_booking_notifications', true)
    
    mail(
      to: business_user.email,
      subject: "New Booking: #{@customer.name} - #{@service.name}"
    )
  end

  # Send notification to business when a new order is placed
  def new_order_notification(order)
    @order = order
    @business = order.business
    @customer = order.tenant_customer
    
    # Check if business user has this notification enabled
    business_user = @business.users.where(role: [:manager, :owner]).first
    return unless business_user&.notification_preferences&.fetch('email_order_notifications', true)
    
    mail(
      to: business_user.email,
      subject: "New Order: #{@customer.name} - Order ##{@order.id}"
    )
  end

  # Send notification to business when a new customer registers
  def new_customer_notification(tenant_customer)
    @customer = tenant_customer
    @business = tenant_customer.business
    
    # Check if business user has this notification enabled
    business_user = @business.users.where(role: [:manager, :owner]).first
    return unless business_user&.notification_preferences&.fetch('email_customer_notifications', true)
    
    mail(
      to: business_user.email,
      subject: "New Customer: #{@customer.name}"
    )
  end

  # Send notification to business when a payment is received
  def payment_received_notification(payment)
    @payment = payment
    @business = payment.business
    @customer = payment.tenant_customer
    @invoice = payment.invoice
    @booking = @invoice&.booking
    @order = @invoice&.order
    
    # Check if business user has this notification enabled
    business_user = @business.users.where(role: [:manager, :owner]).first
    return unless business_user&.notification_preferences&.fetch('email_payment_notifications', true)
    
    subject = if @booking
      "Payment Received: #{@customer.name} - #{@booking.service.name}"
    elsif @order
      "Payment Received: #{@customer.name} - Order ##{@order.id}"
    else
      "Payment Received: #{@customer.name}"
    end
    
    mail(
      to: business_user.email,
      subject: subject
    )
  end
end 