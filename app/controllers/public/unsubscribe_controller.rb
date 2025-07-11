# frozen_string_literal: true

class Public::UnsubscribeController < Public::BaseController
  before_action :find_recipient_by_token, only: [:show, :update, :resubscribe]

  # GET /unsubscribe?token=...&type=marketing
  def show
    if @recipient.nil?
      render :invalid_token
    elsif @recipient.unsubscribed_from_emails?
      render :already_unsubscribed
    else
      @email_type = params[:type]
      render :confirm_unsubscribe
    end
  end

  # PATCH /unsubscribe?token=...&type=marketing
  def update
    if @recipient.nil?
      render :invalid_token
    elsif @recipient.unsubscribed_from_emails?
      render :already_unsubscribed
    else
      @email_type = params[:type]
      
      if @email_type.present?
        # Granular unsubscribe for specific email type
        unsubscribe_from_email_type(@email_type)
        log_unsubscribe_event(@email_type)
      else
        # Global unsubscribe (all emails)
        @recipient.unsubscribe_from_emails!
        log_unsubscribe_event('all')
      end
      
      render :unsubscribed
    end
  end

  # PATCH /unsubscribe/resubscribe?token=...
  def resubscribe
    if @recipient.nil?
      render :invalid_token
    elsif @recipient.subscribed_to_emails?
      render :already_subscribed
    else
      @recipient.resubscribe_to_emails!
      log_resubscribe_event
      render :resubscribed
    end
  end

  private

  def find_recipient_by_token
    token = params[:token]
    return if token.blank?

    # Try to find by User first, then TenantCustomer
    @recipient = User.find_by(unsubscribe_token: token) ||
                 TenantCustomer.find_by(unsubscribe_token: token)
  end

  def unsubscribe_from_email_type(email_type)
    return unless @recipient.respond_to?(:notification_preferences)
    
    # Map email type to notification preference keys
    type_to_preferences = {
      'marketing' => %w[email_marketing_notifications email_promotional_offers email_marketing_updates email_promotions],
      'blog' => %w[email_blog_notifications email_blog_updates blog_post_notifications],
      'booking' => %w[email_booking_notifications email_booking_confirmation email_booking_updates],
      'order' => %w[email_order_notifications email_order_updates],
      'payment' => %w[email_payment_notifications email_payment_confirmations],
      'customer' => %w[email_customer_notifications],
      'system' => %w[system_notifications]
    }
    
    preferences_to_disable = type_to_preferences[email_type] || []
    return if preferences_to_disable.empty?
    
    # Update notification preferences to disable the specific type
    updated_preferences = @recipient.notification_preferences || {}
    preferences_to_disable.each do |pref|
      updated_preferences[pref] = false
    end
    
    @recipient.update(notification_preferences: updated_preferences)
  end

  def log_unsubscribe_event(email_type = 'all')
    type_info = email_type == 'all' ? 'all emails' : "#{email_type} emails"
    Rails.logger.info "[UNSUBSCRIBE] #{@recipient.class.name} ##{@recipient.id} (#{@recipient.email}) unsubscribed from #{type_info}"
  end

  def log_resubscribe_event
    Rails.logger.info "[RESUBSCRIBE] #{@recipient.class.name} ##{@recipient.id} (#{@recipient.email}) resubscribed to emails"
  end
end 