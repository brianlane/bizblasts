# frozen_string_literal: true

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
    @booking = booking
    @business = booking.business
    
    # Handle case where business might be nil or deleted
    unless @business.present?
      Rails.logger.warn "[BusinessMailer] Business not present for Booking ##{booking.id}, skipping notification"
      return
    end
    
    @customer = booking.tenant_customer
    @service = booking.service
    @staff_member = booking.staff_member
    
    # Check if business user has this notification enabled (fixed role reference)
    business_user = @business.users.where(role: [:manager]).first
    
    unless business_user.present?
      Rails.logger.warn "[BusinessMailer] No manager user found for Business ##{@business.id}, skipping notification"
      return
    end
    
    # Check for valid email
    if business_user.email.blank? || !business_user.email.match?(URI::MailTo::EMAIL_REGEXP)
      Rails.logger.warn "[BusinessMailer] Invalid or missing manager email for Business ##{@business.id}, skipping notification"
      return
    end
    
    # Check if the manager has booking notifications enabled
    unless notification_enabled?(business_user, 'email_booking_notifications')
      Rails.logger.info "[BusinessMailer] Email booking notifications disabled for Business ##{@business.id}"
      return
    end
    
    mail(
      to: business_user.email,
      subject: "New Booking: #{@customer.full_name} - #{@service.name}"
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
    
    # Get business manager
    business_user = @business.users.where(role: [:manager]).first
    return unless business_user.present?
    
    # Check for valid email
    return if business_user.email.blank? || !business_user.email.match?(URI::MailTo::EMAIL_REGEXP)
    
    # Check if the manager has order notifications enabled
    unless notification_enabled?(business_user, 'email_order_notifications')
      Rails.logger.info "[BusinessMailer] Email order notifications disabled for Business ##{@business.id}"
      return
    end
    
    mail(
      to: business_user.email,
      subject: "New Order: #{@customer.full_name} - Order ##{@order.id}"
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
    
    # Get business manager
    business_user = @business.users.where(role: [:manager]).first
    return unless business_user.present?
    
    # Check for valid email
    return if business_user.email.blank? || !business_user.email.match?(URI::MailTo::EMAIL_REGEXP)
    
    # Check if the manager has customer notifications enabled
    unless notification_enabled?(business_user, 'email_customer_notifications')
      Rails.logger.info "[BusinessMailer] Email customer notifications disabled for Business ##{@business.id}"
      return
    end
    
    mail(
      to: business_user.email,
      subject: "New Customer: #{@customer.full_name}"
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
    
    # Get business manager
    business_user = @business.users.where(role: [:manager]).first
    return unless business_user.present?
    
    # Check for valid email
    return if business_user.email.blank? || !business_user.email.match?(URI::MailTo::EMAIL_REGEXP)
    
    # Check if the manager has payment notifications enabled
    unless notification_enabled?(business_user, 'email_payment_notifications')
      Rails.logger.info "[BusinessMailer] Email payment notifications disabled for Business ##{@business.id}"
      return
    end
    
    subject = if @booking
      "Payment Received: #{@customer.full_name} - #{@booking.service.name}"
    elsif @order
      "Payment Received: #{@customer.full_name} - Order ##{@order.id}"
    else
      "Payment Received: #{@customer.full_name}"
    end
    
    mail(
      to: business_user.email,
      subject: subject
    )
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "[BusinessMailer] Business not found for payment notification: #{e.message}"
    return nil
  end

  # Send notification to business when a new subscription is created
  def new_subscription_notification(customer_subscription)
    @customer_subscription = customer_subscription
    @business = customer_subscription.business
    
    # Handle case where business might be nil or deleted
    return unless @business.present?
    
    @customer = customer_subscription.tenant_customer
    @item = customer_subscription.product || customer_subscription.service
    
    # Get business manager
    business_user = @business.users.where(role: [:manager]).first
    return unless business_user.present?
    
    # Check for valid email
    return if business_user.email.blank? || !business_user.email.match?(URI::MailTo::EMAIL_REGEXP)
    
    # Check if the manager has subscription notifications enabled
    unless notification_enabled?(business_user, 'email_subscription_notifications')
      Rails.logger.info "[BusinessMailer] Email subscription notifications disabled for Business ##{@business.id}"
      return
    end
    
    # Check if the manager has opted out of marketing emails
    if business_user.email_marketing_opt_out == true
      Rails.logger.info "[BusinessMailer] Manager has opted out of marketing emails for Business ##{@business.id}"
      return
    end
    
    mail(
      to: business_user.email,
      subject: "New Subscription: #{@customer.full_name} - #{@item.name}"
    )
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "[BusinessMailer] Business not found for subscription notification: #{e.message}"
    return nil
  end

  # Send notification to business when a subscription order is created
  def subscription_order_received(customer_subscription, order = nil)
    # Handle both calling patterns
    if order.nil?
      # Old pattern: subscription_order_received(order)
      @order = customer_subscription
      @customer_subscription = @order.customer_subscription
      @business = @order.business
      @customer = @order.tenant_customer
    else
      # New pattern: subscription_order_received(subscription, order)
      @customer_subscription = customer_subscription
      @order = order
      @business = @customer_subscription.business
      @customer = @customer_subscription.tenant_customer
    end
    
    # Handle case where business might be nil or deleted
    return unless @business.present?
    
    # Get business manager
    business_user = @business.users.where(role: [:manager]).first
    return unless business_user.present?
    
    # Check for valid email
    return if business_user.email.blank? || !business_user.email.match?(URI::MailTo::EMAIL_REGEXP)
    
    # Check if the manager has subscription notifications enabled
    unless notification_enabled?(business_user, 'email_subscription_notifications')
      Rails.logger.info "[BusinessMailer] Email subscription notifications disabled for Business ##{@business.id}"
      return
    end
    
    mail(
      to: business_user.email,
      subject: "Subscription Order: #{@customer.full_name} - Order ##{@order.id}"
    )
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "[BusinessMailer] Business not found for subscription order notification: #{e.message}"
    return nil
  end

  # Send notification to business when a subscription booking is created
  def subscription_booking_received(customer_subscription, booking = nil)
    # Handle both calling patterns
    if booking.nil?
      # Old pattern: subscription_booking_received(booking)
      @booking = customer_subscription
      @customer_subscription = @booking.customer_subscription
      @business = @booking.business
      @customer = @booking.tenant_customer
      @service = @booking.service
      @staff_member = @booking.staff_member
    else
      # New pattern: subscription_booking_received(subscription, booking)
      @customer_subscription = customer_subscription
      @booking = booking
      @business = @customer_subscription.business
      @customer = @customer_subscription.tenant_customer
      @service = @booking.service
      @staff_member = @booking.staff_member
    end
    
    # Handle case where business might be nil or deleted
    return unless @business.present?
    
    # Get business manager
    business_user = @business.users.where(role: [:manager]).first
    return unless business_user.present?
    
    # Check for valid email
    return if business_user.email.blank? || !business_user.email.match?(URI::MailTo::EMAIL_REGEXP)
    
    # Check if the manager has subscription notifications enabled
    unless notification_enabled?(business_user, 'email_subscription_notifications')
      Rails.logger.info "[BusinessMailer] Email subscription notifications disabled for Business ##{@business.id}"
      return
    end
    
    mail(
      to: business_user.email,
      subject: "Subscription Booking: #{@customer.full_name} - #{@service.name}"
    )
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "[BusinessMailer] Business not found for subscription booking notification: #{e.message}"
    return nil
  end

  # Send notification to business when a subscription payment fails
  def payment_failed(customer_subscription)
    @customer_subscription = customer_subscription
    @business = customer_subscription.business
    
    # Handle case where business might be nil or deleted
    return unless @business.present?
    
    @customer = customer_subscription.tenant_customer
    @item = customer_subscription.product || customer_subscription.service
    
    # Get business manager
    business_user = @business.users.where(role: [:manager]).first
    return unless business_user.present?
    
    # Check for valid email
    return if business_user.email.blank? || !business_user.email.match?(URI::MailTo::EMAIL_REGEXP)
    
    # Check if the manager has subscription notifications enabled
    unless notification_enabled?(business_user, 'email_subscription_notifications')
      Rails.logger.info "[BusinessMailer] Email subscription notifications disabled for Business ##{@business.id}"
      return
    end
    
    mail(
      to: business_user.email,
      subject: "Subscription Payment Failed: #{@customer.full_name} - #{@item.name}"
    )
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "[BusinessMailer] Business not found for payment failed notification: #{e.message}"
    return nil
  end

  # Send notification to business when a subscription is cancelled
  def subscription_cancelled(customer_subscription)
    @customer_subscription = customer_subscription
    @business = customer_subscription.business
    
    # Handle case where business might be nil or deleted
    return unless @business.present?
    
    @customer = customer_subscription.tenant_customer
    @item = customer_subscription.product || customer_subscription.service
    
    # Get business manager
    business_user = @business.users.where(role: [:manager]).first
    return unless business_user.present?
    
    # Check for valid email
    return if business_user.email.blank? || !business_user.email.match?(URI::MailTo::EMAIL_REGEXP)
    
    # Check if the manager has subscription notifications enabled
    unless notification_enabled?(business_user, 'email_subscription_notifications')
      Rails.logger.info "[BusinessMailer] Email subscription notifications disabled for Business ##{@business.id}"
      return
    end
    
    mail(
      to: business_user.email,
      subject: "Subscription Cancelled: #{@customer.full_name} - #{@item.name}"
    )
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "[BusinessMailer] Business not found for subscription cancelled notification: #{e.message}"
    return nil
  end

  private

  def notification_enabled?(user, notification_type)
    preferences = user.notification_preferences
    
    # If no preferences are set, default to enabled
    return true if preferences.nil? || preferences.empty?
    
    # Check the specific notification type
    preferences[notification_type] == true
  end
end 