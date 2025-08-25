# frozen_string_literal: true

require 'ostruct'

class BusinessMailer < ApplicationMailer
  # Send domain request notification to premium business users after email confirmation
  def domain_request_notification(user)
    return unless user.can_receive_email?(:system)
    @user = user
    @business = user.business
    
    # Handle case where business might be nil or deleted
    return unless @business.present?
    
    @domain_requested = @business.hostname if @business.host_type_custom_domain?
    @subdomain_requested = @business.subdomain
    @custom_domain_owned = @business.custom_domain_owned || false
    
    # Set unsubscribe token for the user
    set_unsubscribe_token(user)
    
    mail(
      to: @user.email,
      subject: "Custom Domain Request Received - #{@business.name}",
      reply_to: @support_email
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
    
    # Check if the manager can receive booking emails
    return unless business_user.can_receive_email?(:booking)
    
    # Set unsubscribe token for the business user
    set_unsubscribe_token(business_user)
    
    mail(
      to: business_user.email,
      subject: "New Booking: #{@customer.full_name} - #{@service.name}",
      reply_to: @support_email
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
    
    # Check if the manager can receive order emails
    return unless business_user.can_receive_email?(:order)
    
    # Set unsubscribe token for the business user
    set_unsubscribe_token(business_user)
    
    mail(
      to: business_user.email,
      subject: "New Order: #{@customer.full_name} - Order ##{@order.id}",
      reply_to: @support_email
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
    
    # Set tenant context properly for secure scoping
    ActsAsTenant.with_tenant(@business) do
      @customer_user_account = nil
      
      if @customer.email.present?
        # Look for user account within business context only
        @customer_user_account = @business.users.find_by(email: @customer.email)
      end
    end
    
    # Get business manager
    business_user = @business.users.where(role: [:manager]).first
    return unless business_user.present?
    
    # Check for valid email
    return if business_user.email.blank? || !business_user.email.match?(URI::MailTo::EMAIL_REGEXP)
    
    # Check if the manager can receive customer emails
    return unless business_user.can_receive_email?(:customer)
    
    # Set unsubscribe token for the business user
    set_unsubscribe_token(business_user)
    
    mail(
      to: business_user.email,
      subject: "New Customer: #{@customer.full_name}",
      reply_to: @support_email
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
    
    # Check if the manager can receive payment emails
    return unless business_user.can_receive_email?(:payment)
    
    # Set unsubscribe token for the business user
    set_unsubscribe_token(business_user)
    
    subject = if @booking
      "Payment Received: #{@customer.full_name} - #{@booking.service.name}"
    elsif @order
      "Payment Received: #{@customer.full_name} - Order ##{@order.id}"
    else
      "Payment Received: #{@customer.full_name}"
    end
    
    mail(
      to: business_user.email,
      subject: subject,
      reply_to: @support_email
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
    
    # Check if the manager can receive subscription emails
    return unless business_user.can_receive_email?(:subscription)
    
    mail(
      to: business_user.email,
      subject: "New Subscription: #{@customer.full_name} - #{@item.name}",
      reply_to: @support_email
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
    
    # Check if the manager can receive order emails
    return unless business_user.can_receive_email?(:order)
    
    mail(
      to: business_user.email,
      subject: "Subscription Order: #{@customer.full_name} - Order ##{@order.id}",
      reply_to: @support_email
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
    
    # Check if the manager can receive booking emails
    return unless business_user.can_receive_email?(:booking)
    
    mail(
      to: business_user.email,
      subject: "Subscription Booking: #{@customer.full_name} - #{@service.name}",
      reply_to: @support_email
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
    
    # Check if the manager can receive payment emails
    return unless business_user.can_receive_email?(:payment)
    
    mail(
      to: business_user.email,
      subject: "Subscription Payment Failed: #{@customer.full_name} - #{@item.name}",
      reply_to: @support_email
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
    
    # Check if the manager can receive subscription emails
    return unless business_user.can_receive_email?(:subscription)
    
    mail(
      to: business_user.email,
      subject: "Subscription Cancelled: #{@customer.full_name} - #{@item.name}",
      reply_to: @support_email
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

  # Helper to generate tenant URLs in mailer templates
  def tenant_url_for(business, path = '/')
    # Create a proper mock request object for mailer context
    mock_request = OpenStruct.new(
      protocol: Rails.env.production? ? 'https://' : 'http://',
      domain: Rails.env.development? || Rails.env.test? ? 'lvh.me' : 'bizblasts.com',
      port: Rails.env.development? ? 3000 : (Rails.env.production? ? 443 : 80)
    )
    TenantHost.url_for(business, mock_request, path)
  end
  helper_method :tenant_url_for
end 