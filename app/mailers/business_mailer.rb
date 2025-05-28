class BusinessMailer < ApplicationMailer
  # Send domain request notification to premium business users after email confirmation
  def domain_request_notification(user)
    @user = user
    @business = user.business
    
    # Handle case where business might be nil or deleted
    return unless @business.present?
    
    @domain_requested = @business.hostname if @business.host_type_custom_domain?
    
    mail(
      to: @user.email,
      subject: "Custom Domain Request Received - #{@business.name}"
    )
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "[BusinessMailer] Business not found for domain request notification: #{e.message}"
    return nil
  end

  # Send notification to business when a new booking is made
  def new_booking_notification(booking)
    Rails.logger.info "[BusinessMailer] Starting new_booking_notification for Booking ##{booking.id}"
    
    @booking = booking
    @business = booking.business
    
    # Handle case where business might be nil or deleted
    unless @business.present?
      Rails.logger.warn "[BusinessMailer] Business not present for Booking ##{booking.id}, skipping notification"
      return
    end
    
    Rails.logger.info "[BusinessMailer] Business found: ##{@business.id} (#{@business.name})"
    
    @customer = booking.tenant_customer
    @service = booking.service
    @staff_member = booking.staff_member
    
    # Check if business user has this notification enabled (fixed role reference)
    business_user = @business.users.where(role: [:manager]).first
    Rails.logger.info "[BusinessMailer] Business users with manager role: #{@business.users.where(role: [:manager]).count}"
    
    unless business_user.present?
      Rails.logger.warn "[BusinessMailer] No manager user found for Business ##{@business.id}, skipping notification"
      return
    end
    
    Rails.logger.info "[BusinessMailer] Manager user found: #{business_user.email}"
    
    notification_enabled = business_user&.notification_preferences&.fetch('email_booking_notifications', true)
    Rails.logger.info "[BusinessMailer] Email booking notifications enabled: #{notification_enabled}"
    Rails.logger.info "[BusinessMailer] Notification preferences: #{business_user.notification_preferences}"
    
    unless notification_enabled
      Rails.logger.warn "[BusinessMailer] Email booking notifications disabled for user #{business_user.email}, skipping notification"
      return
    end
    
    Rails.logger.info "[BusinessMailer] Preparing email to #{business_user.email} for booking notification"
    
    mail(
      to: business_user.email,
      subject: "New Booking: #{@customer.name} - #{@service.name}"
    )
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "[BusinessMailer] Business not found for booking notification: #{e.message}"
    return nil
  end

  # Send notification to business when a new order is placed
  def new_order_notification(order)
    @order = order
    @business = order.business
    
    # Handle case where business might be nil or deleted
    return unless @business.present?
    
    @customer = order.tenant_customer
    
    # Check if business user has this notification enabled (fixed role reference)
    business_user = @business.users.where(role: [:manager]).first
    return unless business_user&.notification_preferences&.fetch('email_order_notifications', true)
    
    mail(
      to: business_user.email,
      subject: "New Order: #{@customer.name} - Order ##{@order.id}"
    )
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "[BusinessMailer] Business not found for order notification: #{e.message}"
    return nil
  end

  # Send notification to business when a new customer registers
  def new_customer_notification(tenant_customer)
    @customer = tenant_customer
    @business = tenant_customer.business
    
    # Handle case where business might be nil or deleted
    return unless @business.present?
    
    # Check if business user has this notification enabled (fixed role reference)
    business_user = @business.users.where(role: [:manager]).first
    return unless business_user&.notification_preferences&.fetch('email_customer_notifications', true)
    
    mail(
      to: business_user.email,
      subject: "New Customer: #{@customer.name}"
    )
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "[BusinessMailer] Business not found for customer notification: #{e.message}"
    return nil
  end

  # Send notification to business when a payment is received
  def payment_received_notification(payment)
    @payment = payment
    @business = payment.business
    
    # Handle case where business might be nil or deleted
    return unless @business.present?
    
    @customer = payment.tenant_customer
    @invoice = payment.invoice
    @booking = @invoice&.booking
    @order = @invoice&.order
    
    # Check if business user has this notification enabled (fixed role reference)
    business_user = @business.users.where(role: [:manager]).first
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
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "[BusinessMailer] Business not found for payment notification: #{e.message}"
    return nil
  end
end 