# frozen_string_literal: true

class TenantCustomer < ApplicationRecord
  include TenantScoped
  include UnsubscribeTokenGenerator
  
  acts_as_tenant(:business)
  belongs_to :business
  belongs_to :user, optional: true
  has_many :bookings, dependent: :destroy
  has_many :invoices, dependent: :destroy
  has_many :orders, dependent: :destroy
  has_many :payments, dependent: :destroy
  has_many :sms_messages, dependent: :destroy
  has_many :client_documents, as: :documentable, dependent: :nullify
  
  # Loyalty and referral system associations
  has_many :loyalty_transactions, dependent: :destroy
  has_many :loyalty_redemptions, dependent: :destroy
  
  # Subscription associations
  has_many :customer_subscriptions, dependent: :destroy
  has_many :subscription_transactions, dependent: :destroy
  
  # Allow access to User accounts associated with this customer's business
  has_many :users, through: :business, source: :clients

  # Encrypt phone numbers with deterministic encryption to allow querying
  encrypts :phone, deterministic: true

  # Base validations - updated to match User model
  validates :first_name, length: { maximum: 255 }, allow_blank: true
  validates :last_name, length: { maximum: 255 }, allow_blank: true
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  # Note: uniqueness is now enforced by database index on business_id + LOWER(email)
  # Phone is optional - remove conflicting validation rules
  # validates :phone, presence: true, allow_blank: true  # This was contradictory
  
  # Callbacks
  after_create :send_business_customer_notification
  after_create :generate_unsubscribe_token
  after_create :set_default_email_preferences
  after_create_commit :sync_to_email_marketing_on_create
  after_update_commit :sync_to_email_marketing_on_update
  before_validation :normalize_email
  before_validation :normalize_phone_number
  validate :unique_email_per_business
  
  # Add accessor to skip email notifications when handled by staggered delivery
  attr_accessor :skip_notification_email
  attr_accessor :skip_email_marketing_sync
  
  scope :active, -> { where(active: true) }
  scope :subscribed_to_emails, -> { where(unsubscribed_at: nil) }
  scope :unsubscribed_from_emails, -> { where.not(unsubscribed_at: nil) }
  
  # Encrypted phone lookup scopes
  scope :for_phone, ->(plain_phone) {
    normalized = PhoneNormalizer.normalize(plain_phone)
    return none if normalized.blank?

    where(phone: normalized)
  }

  scope :for_phone_set, ->(phones) {
    normalized_set = PhoneNormalizer.normalize_collection(phones)
    return none if normalized_set.blank?

    where(phone: normalized_set)
  }
  
  scope :with_phone, -> { where.not(phone: nil) }
  
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
  # Note: phone excluded from ransackable attributes because it's encrypted and doesn't support partial searches
  def self.ransackable_attributes(auth_object = nil)
    %w[id first_name last_name email address notes active last_booking created_at updated_at business_id]
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
    return false if opted_out_from_business?(business) # Business-specific opt-out takes precedence
    return true if type == :transactional && phone_opt_in? # Allow transactional if opted in

    # Check specific SMS opt-in status and notification preferences
    case type.to_sym
    when :marketing
      # Marketing SMS requires explicit opt-in AND business marketing enabled AND not opted out
      phone_opt_in? && business.sms_marketing_enabled? && !phone_marketing_opt_out? && sms_preference_enabled?('sms_promotions')
    when :booking
      # Booking SMS requires phone opt-in and booking confirmation preference
      phone_opt_in? && sms_preference_enabled?('sms_booking_reminder')
    when :reminder
      # Reminder SMS requires phone opt-in and booking reminder preference  
      phone_opt_in? && sms_preference_enabled?('sms_booking_reminder')
    when :order
      # Order SMS requires phone opt-in and order update preference
      phone_opt_in? && sms_preference_enabled?('sms_order_updates')
    when :payment, :system, :subscription, :review_request
      # Other SMS types require general phone opt-in (no specific preference controls in UI yet)
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

  # Business-specific opt-out methods
  def opted_out_from_business?(business)
    return false unless sms_opted_out_businesses.present?
    sms_opted_out_businesses.include?(business.id)
  end

  def opt_out_from_business!(business)
    self.sms_opted_out_businesses ||= []
    unless opted_out_from_business?(business)
      self.sms_opted_out_businesses = sms_opted_out_businesses + [business.id]
      save!
      Rails.logger.info "[SMS_OPT_OUT] Customer #{id} opted out from business #{business.id} (#{business.name})"
    end
  end

  def opt_in_to_business!(business)
    return unless sms_opted_out_businesses.present?
    if opted_out_from_business?(business)
      self.sms_opted_out_businesses = sms_opted_out_businesses - [business.id]
      save!
      Rails.logger.info "[SMS_OPT_IN] Customer #{id} opted back in to business #{business.id} (#{business.name})"
    end
  end

  def can_receive_invitation_from?(business)
    return false if opted_out_from_business?(business)
    # Check 30-day limit
    !SmsOptInInvitation.recent_invitation_sent?(phone, business.id)
  end

  # Check if phone number appears valid for SMS
  def phone_verified?
    phone.present? && phone.match?(/\A\+?[1-9]\d{1,14}\z/)
  end

  # Check if a specific SMS notification preference is enabled
  # TenantCustomer checks the associated User's notification preferences (for client users)
  def sms_preference_enabled?(preference_key)
    # Find the associated client User by email
    associated_user = User.find_by(email: email, role: 'client')
    
    # If no associated user or no notification preferences are set, default to true (allow all)
    return true unless associated_user
    return true if associated_user.notification_preferences.nil? || associated_user.notification_preferences.empty?
    
    # Check if the preference is enabled in the User's preferences
    # Treat nil as enabled (default) to maintain backward compatibility
    # Only false explicitly disables notifications
    preference_value = associated_user.notification_preferences[preference_key]
    preference_value != false
  end

  # Simple accessor used by specs to check notification enablement
  # Falls back to true when no preference is explicitly disabled.
  def notification_enabled?(pref_key)
    if user&.notification_preferences.present?
      # treat nil as enabled
      user.notification_preferences[pref_key] != false
    else
      true
    end
  end

  private

  def normalize_email
    self.email = email.downcase.strip if email.present?
  end

  def normalize_phone_number
    self.phone = PhoneNormalizer.normalize(phone)
  end

  def unique_email_per_business
    return unless email.present? && business_id.present?
    
    # Check for existing customer with same email in same business
    existing = TenantCustomer.where(
      business_id: business_id,
      email: email.downcase.strip
    )
    existing = existing.where.not(id: id) unless new_record?
    
    if existing.exists?
      errors.add(:email, "must be unique within this business")
    end
  end

  def set_default_email_preferences
    # TenantCustomers are simpler - ensure email_marketing_opt_out defaults to false (allowing emails)
    # and unsubscribed_at remains nil (subscribed by default)
    return if email_marketing_opt_out == true || unsubscribed_at.present?
    
    # Explicitly set to false to ensure emails are enabled by default
    if email_marketing_opt_out.nil?
      if update_attribute(:email_marketing_opt_out, false)
        SecureLogger.info "[TENANT_CUSTOMER] Set default email preferences for TenantCustomer ##{id} (#{email})"
      else
        SecureLogger.error "[TENANT_CUSTOMER] Failed to set default email preferences for TenantCustomer ##{id} (#{email})"
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
        BusinessMailer.new_customer_notification(self).deliver_later(queue: 'mailers') if business_user.can_receive_email?(:customer)

        # Send SMS if opted in
        if business_user.respond_to?(:can_receive_sms?) && business_user.can_receive_sms?(:booking)
          SmsService.send_business_new_customer(self, business_user)
        end
      end
      SecureLogger.info "[NOTIFICATION] Scheduled business customer notification for Customer #{full_name} (#{email})"
    rescue => e
      SecureLogger.error "[NOTIFICATION] Failed to schedule business customer notification for Customer #{full_name} (#{email}): #{e.message}"
    end
  end

  # Sync customer to email marketing platforms on create
  def sync_to_email_marketing_on_create
    return if skip_email_marketing_sync
    return unless email.present? && active?

    # Find connections that should sync on customer create
    business.email_marketing_connections.active.where(sync_on_customer_create: true).find_each do |connection|
      EmailMarketing::SyncSingleContactJob.perform_later(id, connection.provider, 'sync')
    end
  rescue StandardError => e
    Rails.logger.error "[TenantCustomer] Failed to queue email marketing sync on create: #{e.message}"
  end

  # Sync customer to email marketing platforms on update
  def sync_to_email_marketing_on_update
    return if skip_email_marketing_sync
    return unless email.present?

    # Check if relevant fields changed
    sync_relevant_changes = saved_changes.keys & %w[email first_name last_name phone active email_marketing_opt_out unsubscribed_at]
    return if sync_relevant_changes.empty?

    # Handle deactivation specially - remove from email marketing
    if saved_changes.key?('active') && !active?
      business.email_marketing_connections.active.find_each do |connection|
        EmailMarketing::SyncSingleContactJob.perform_later(id, connection.provider, 'remove')
      end
      return
    end

    # For inactive customers, only process opt-out/unsubscribe changes
    # Do NOT sync regular field updates for inactive customers to providers
    # This preserves the deactivation semantics
    unless active?
      # Handle opt-out/unsubscribe changes even for inactive customers
      opt_out_changed = saved_changes.key?('email_marketing_opt_out') && email_marketing_opt_out?
      unsubscribed_changed = saved_changes.key?('unsubscribed_at') && unsubscribed_at.present?

      if opt_out_changed || unsubscribed_changed
        business.email_marketing_connections.active.find_each do |connection|
          EmailMarketing::SyncSingleContactJob.perform_later(id, connection.provider, 'opt_out')
        end
      end
      return
    end

    # Handle opt-out/unsubscribe changes - these must always sync regardless of auto-sync settings
    # to ensure unsubscribe preferences are respected by email marketing providers
    opt_out_changed = saved_changes.key?('email_marketing_opt_out') && email_marketing_opt_out?
    unsubscribed_changed = saved_changes.key?('unsubscribed_at') && unsubscribed_at.present?

    if opt_out_changed || unsubscribed_changed
      # Customer opted out or unsubscribed - update status in providers
      # Use 'opt_out' action to ensure this syncs even if auto-sync is disabled
      business.email_marketing_connections.active.find_each do |connection|
        EmailMarketing::SyncSingleContactJob.perform_later(id, connection.provider, 'opt_out')
      end
      return
    end

    # Regular update - sync to platforms that sync on update (only for active customers)
    business.email_marketing_connections.active.where(sync_on_customer_update: true).find_each do |connection|
      EmailMarketing::SyncSingleContactJob.perform_later(id, connection.provider, 'sync')
    end
  rescue StandardError => e
    Rails.logger.error "[TenantCustomer] Failed to queue email marketing sync on update: #{e.message}"
  end
end