# frozen_string_literal: true

class TenantCustomer < ApplicationRecord
  include TenantScoped
  include UnsubscribeTokenGenerator
  
  acts_as_tenant(:business)
  belongs_to :business
  has_many :bookings, dependent: :destroy
  has_many :invoices, dependent: :destroy
  has_many :orders, dependent: :destroy
  has_many :payments, dependent: :destroy
  has_many :sms_messages, dependent: :destroy
  
  # Loyalty and referral system associations
  has_many :loyalty_transactions, dependent: :destroy
  has_many :loyalty_redemptions, dependent: :destroy
  
  # Subscription associations
  has_many :customer_subscriptions, dependent: :destroy
  has_many :subscription_transactions, dependent: :destroy
  
  # Allow access to User accounts associated with this customer's business
  has_many :users, through: :business, source: :clients
  
  # Base validations - updated to match User model
  validates :first_name, presence: true
  validates :last_name, presence: true
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, uniqueness: { scope: :business_id, message: "must be unique within this business" }
  # Make phone optional for now to fix booking flow
  validates :phone, presence: true, allow_blank: true
  
  # Callbacks
  after_create :send_business_customer_notification
  after_create :generate_unsubscribe_token
  after_create :set_default_email_preferences
  
  # Add accessor to skip email notifications when handled by staggered delivery
  attr_accessor :skip_notification_email
  
  scope :active, -> { where(active: true) }
  scope :subscribed_to_emails, -> { where(unsubscribed_at: nil) }
  scope :unsubscribed_from_emails, -> { where.not(unsubscribed_at: nil) }
  
  def full_name
    [first_name, last_name].compact.join(' ').presence || email
  end
  
  # Backward compatibility method for old references
  alias_method :name, :full_name
  
  def name_with_email
    "#{full_name} (#{email})"
  end
  
  def recent_bookings
    bookings.order(start_time: :desc).limit(5)
  end
  
  def upcoming_bookings
    bookings.where('start_time > ?', Time.now).order(start_time: :asc)
  end
  
  def current_business
    Business.find(business_id)
  end
  
  # Cached loyalty points methods for better performance
  def current_loyalty_points
    Rails.cache.fetch("tenant_customer_#{id}_loyalty_points", expires_in: 1.hour) do
      loyalty_transactions.sum(:points_amount)
    end
  end
  
  def loyalty_points_earned
    Rails.cache.fetch("tenant_customer_#{id}_loyalty_points_earned", expires_in: 1.hour) do
      loyalty_transactions.earned.sum(:points_amount)
    end
  end
  
  def loyalty_points_redeemed
    Rails.cache.fetch("tenant_customer_#{id}_loyalty_points_redeemed", expires_in: 1.hour) do
      loyalty_transactions.redeemed.sum(:points_amount).abs
    end
  end
  
  def loyalty_points_history
    loyalty_transactions.recent.limit(20)
  end
  
  def can_redeem_points?(points_required)
    current_loyalty_points >= points_required
  end
  
  def add_loyalty_points!(points, description, related_record = nil)
    loyalty_transactions.create!(
      business: business,
      transaction_type: 'earned',
      points_amount: points,
      description: description,
      related_booking: related_record.is_a?(Booking) ? related_record : nil,
      related_order: related_record.is_a?(Order) ? related_record : nil
    )
  end
  
  def redeem_loyalty_points!(points, description, related_record = nil)
    return false unless can_redeem_points?(points)
    
    loyalty_transactions.create!(
      business: business,
      transaction_type: 'redeemed',
      points_amount: -points,
      description: description,
      related_booking: related_record.is_a?(Booking) ? related_record : nil,
      related_order: related_record.is_a?(Order) ? related_record : nil
    )
  end
  
  # Clear loyalty cache when transactions change
  def clear_loyalty_cache
    Rails.cache.delete("tenant_customer_#{id}_loyalty_points")
    Rails.cache.delete("tenant_customer_#{id}_loyalty_points_earned")
    Rails.cache.delete("tenant_customer_#{id}_loyalty_points_redeemed")
  end

  # Subscription methods
  def active_subscriptions
    customer_subscriptions.active
  end
  
  def has_active_subscriptions?
    active_subscriptions.exists?
  end
  
  def subscription_for(item)
    if item.is_a?(Product)
      customer_subscriptions.active.product_subscriptions.find_by(product: item)
    elsif item.is_a?(Service)
      customer_subscriptions.active.service_subscriptions.find_by(service: item)
    end
  end
  
  def subscribed_to?(item)
    subscription_for(item).present?
  end
  
  def total_monthly_subscription_cost
    active_subscriptions.sum(:subscription_price)
  end
  
  # Define ransackable attributes for ActiveAdmin - updated for new fields
  def self.ransackable_attributes(auth_object = nil)
    %w[id first_name last_name email phone address notes active last_booking created_at updated_at business_id]
  end
  
  # Define ransackable associations for ActiveAdmin
  def self.ransackable_associations(auth_object = nil)
    %w[business bookings invoices orders]
  end
  
  # Index for faster lookup during uniqueness validation
  # This combined with the index on the database should improve performance
  def self.index_for_email_uniqueness
    @email_business_index ||= {}
  end

  # Unsubscribe system methods
  def unsubscribe_from_emails!
    update!(
      unsubscribed_at: Time.current,
      email_marketing_opt_out: true
    )
  end

  def resubscribe_to_emails!
    update!(
      unsubscribed_at: nil,
      email_marketing_opt_out: false
    )
    regenerate_unsubscribe_token
  end

  def unsubscribed_from_emails?
    unsubscribed_at.present?
  end

  def subscribed_to_emails?
    !unsubscribed_from_emails?
  end
  
  # Returns true if the customer can receive a given type of email (e.g., :marketing, :blog, :booking, etc.)
  def can_receive_email?(type)
    return true if type == :transactional # Always allow transactional emails
    return false if unsubscribed_from_emails?

    # For TenantCustomer, we have simpler logic than User since we don't have granular notification preferences
    # We only check the global unsubscribe status and email_marketing_opt_out for marketing emails
    case type.to_sym
    when :marketing
      # Check if marketing emails are explicitly opted out
      !email_marketing_opt_out?
    when :blog, :booking, :order, :payment, :customer, :system, :subscription
      # For other email types, allow if not globally unsubscribed
      true
    else
      # Default to allow for unknown types
      true
    end
  end

  # Returns true if the customer can receive a given type of SMS (e.g., :marketing, :booking, :transactional, etc.)
  def can_receive_sms?(type)
    return false unless phone.present? # Must have phone number
    return false unless business&.sms_enabled? # Business must have SMS enabled
    return true if type == :transactional && phone_opt_in? # Allow transactional if opted in

    # Check specific SMS opt-in status
    case type.to_sym
    when :marketing
      # Marketing SMS requires explicit opt-in AND business marketing enabled AND not opted out
      phone_opt_in? && business.sms_marketing_enabled? && !phone_marketing_opt_out?
    when :booking, :order, :payment, :reminder, :system, :subscription
      # Other SMS types require general phone opt-in
      phone_opt_in?
    else
      # Default to require opt-in for unknown types
      phone_opt_in?
    end
  end

  # Opt customer into SMS notifications
  def opt_into_sms!
    update!(
      phone_opt_in: true,
      phone_opt_in_at: Time.current
    )
  end

  # Opt customer out of SMS notifications  
  def opt_out_of_sms!
    update!(
      phone_opt_in: false,
      phone_opt_in_at: nil
    )
  end

  # Opt customer out of marketing SMS only
  def opt_out_of_sms_marketing!
    update!(phone_marketing_opt_out: true)
  end

  # Check if phone number appears valid for SMS
  def phone_verified?
    phone.present? && phone.match?(/\A\+?[1-9]\d{1,14}\z/)
  end
  
  private

  def set_default_email_preferences
    # TenantCustomers are simpler - ensure email_marketing_opt_out defaults to false (allowing emails)
    # and unsubscribed_at remains nil (subscribed by default)
    return if email_marketing_opt_out == true || unsubscribed_at.present?
    
    # Explicitly set to false to ensure emails are enabled by default
    if email_marketing_opt_out.nil?
      if update_attribute(:email_marketing_opt_out, false)
        Rails.logger.info "[TENANT_CUSTOMER] Set default email preferences for TenantCustomer ##{id} (#{email})"
      else
        Rails.logger.error "[TENANT_CUSTOMER] Failed to set default email preferences for TenantCustomer ##{id} (#{email})"
      end
    end
  end
  
  def send_business_customer_notification
    # Skip if explicitly disabled (used by staggered email service)
    return if skip_notification_email
    
    begin
      # Create a new customer notification - this will go to business owner
      business_user = business.users.where(role: :manager).first
      if business_user
        # Send email
        BusinessMailer.new_customer_notification(self).deliver_later if business_user.can_receive_email?(:customer)
        
        # Send SMS if opted in
        if business_user.respond_to?(:can_receive_sms?) && business_user.can_receive_sms?(:booking)
          SmsService.send_business_new_customer(self, business_user)
        end
      end
      Rails.logger.info "[NOTIFICATION] Scheduled business customer notification for Customer #{full_name} (#{email})"
    rescue => e
      Rails.logger.error "[NOTIFICATION] Failed to schedule business customer notification for Customer #{full_name} (#{email}): #{e.message}"
    end
  end
end 