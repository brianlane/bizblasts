# frozen_string_literal: true

class CustomerSubscription < ApplicationRecord
  include TenantScoped
  
  acts_as_tenant(:business)
  belongs_to :business
  belongs_to :tenant_customer
  belongs_to :product, optional: true
  belongs_to :service, optional: true
  belongs_to :preferred_staff_member, class_name: 'StaffMember', optional: true
  has_many :subscription_transactions, dependent: :destroy
  has_many :orders, dependent: :destroy
  has_many :line_items, through: :orders
  
  # Enums (must be defined before validations that reference them)
  enum :status, {
    active: 0,
    cancelled: 1,
    expired: 2,
    failed: 3
  }
  
  enum :subscription_type, {
    product_subscription: 'product_subscription',
    service_subscription: 'service_subscription'
  }
  
  enum :frequency, {
    weekly: 'weekly',
    monthly: 'monthly',
    quarterly: 'quarterly',
    annually: 'annually'
  }
  
  enum :service_rebooking_preference, {
    same_staff: 0,
    any_available: 1,
    preferred_staff: 2
  }
  
  enum :out_of_stock_action, {
    skip_delivery: 0,
    substitute_similar: 1,
    contact_customer: 2,
    loyalty_points: 3
  }
  
  # Validations (after enums so they can reference enum keys)
  validates :subscription_type, presence: true, inclusion: { in: subscription_types.keys }
  validates :status, presence: true
  validates :frequency, presence: true
  validates :subscription_price, presence: true, numericality: { greater_than: 0 }
  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :next_billing_date, presence: true
  validate :must_have_product_or_service
  validate :frequency_must_be_valid
  validate :product_belongs_to_business
  validate :service_belongs_to_business
  validate :tenant_customer_belongs_to_business
  validate :preferred_staff_member_belongs_to_business
  
  # Scopes
  scope :active, -> { where(status: :active) }
  scope :product_subscriptions, -> { where(subscription_type: :product_subscription) }
  scope :service_subscriptions, -> { where(subscription_type: :service_subscription) }
  scope :due_for_billing, -> { where('next_billing_date <= ?', Date.current) }
  scope :recent, -> { order(created_at: :desc) }
  
  # Callbacks
  after_create :schedule_first_billing
  after_update :handle_status_changes
  
  # Class methods
  def self.billing_cycles
    frequencies.keys
  end
  
  # Rebooking preferences for service subscriptions
  def self.rebooking_preferences
    {
      'same_day_next_month' => 'Same day next month (or soonest available)',
      'same_day_loyalty_fallback' => 'Same day next month (or loyalty points if unavailable)',
      'business_default' => 'Use business default'
    }
  end
  
    # Service rebooking preferences method for controller compatibility
  def self.service_rebooking_preferences
    rebooking_preferences
  end

  # Instance methods
  def customer_preference_options_for_rebooking
    options = [
      ['Same day next month (or soonest available)', 'same_day_next_month']
    ]
    
    # Add loyalty points option if business has loyalty program enabled
    if business&.loyalty_program_enabled?
      options << ['Same day next month (or loyalty points if unavailable)', 'same_day_loyalty_fallback']
    end
    
    options
  end
  
  def customer_preference_options_for_out_of_stock
    options = [
      ['Skip this delivery', 'skip_delivery'],
      ['Contact me first', 'contact_customer']
    ]
    
    # Add loyalty points option if business has loyalty program enabled
    if business&.loyalty_program_enabled?
      options << ['Receive loyalty points instead', 'loyalty_points']
    end
    
    options
  end
  
  def preference_description(option_value)
    case option_value
    when 'same_day_next_month'
      'We\'ll try to book the same day and time next month. If unavailable, we\'ll book the soonest available slot.'
    when 'same_day_loyalty_fallback'
      'We\'ll try to book the same day and time next month. If unavailable, you\'ll receive loyalty points instead.'
    when 'skip_delivery'
      'We\'ll skip this billing cycle and try again next month.'
    when 'loyalty_points'
      'You\'ll receive loyalty points equal to your subscription value instead of the product/service.'
    when 'contact_customer'
      'We\'ll contact you before taking any action.'
    else
      'Default business preference will be used.'
    end
  end
  def item
    product_subscription? ? product : service
  end
  
  def item_name
    item&.name || 'Unknown Item'
  end
  
  def display_name
    item_name
  end
  
  def billing_cycle
    frequency
  end
  
  def total_amount
    subscription_price * quantity
  end
  
  def has_customer_preferences?
    allow_customer_preferences?
  end
  

  
  def can_be_cancelled?
    active? || failed?
  end
  
  def cancel!
    return false unless can_be_cancelled?
    
    transaction do
      update!(
        status: :cancelled,
        cancelled_at: Time.current
      )

      # Cancel in Stripe if we have a stripe_subscription_id
      if stripe_subscription_id.present?
        begin
          SubscriptionStripeService.new(self).cancel_stripe_subscription!
        rescue Stripe::StripeError => e
          Rails.logger.error "Failed to cancel Stripe subscription #{stripe_subscription_id}: #{e.message}"
          # Continue with local cancellation even if Stripe fails
        end
      end

      # Send notifications
      begin
        SubscriptionMailer.subscription_cancelled(self).deliver_now
        BusinessMailer.subscription_cancelled(self).deliver_now
      rescue => e
        Rails.logger.error "Failed to send cancellation notifications for subscription #{id}: #{e.message}"
        # Continue even if email fails
      end
    end

    true
  rescue => e
    Rails.logger.error "Failed to cancel subscription #{id}: #{e.message}"
    false
  end


  
  
  def calculate_next_billing_date
    current_date = next_billing_date
    
    base_date = if weekly?
      current_date + 1.week
    elsif monthly?
      # Use advance to properly handle month boundaries
      current_date.advance(months: 1)
    elsif quarterly?
      current_date.advance(months: 3)
    elsif annually?
      current_date.advance(years: 1)
    else
      current_date.advance(months: 1)
    end
    
    # Apply billing day of month preference for monthly+ frequencies
    # Only apply if billing_day_of_month is set and > 0 (0 means no preference)
    if billing_day_of_month.present? && billing_day_of_month > 0 && (monthly? || quarterly? || annually?)
      # Adjust to the preferred day of the month
      target_day = billing_day_of_month.to_i
      
      # Get the month/year of the base date
      year = base_date.year
      month = base_date.month
      
      # Handle edge case where target day doesn't exist in the month (e.g., Feb 30)
      last_day_of_month = Date.new(year, month, -1).day
      actual_day = [target_day, last_day_of_month].min
      
      Date.new(year, month, actual_day)
    else
      base_date
    end
  end
  
  def process_billing!
    return false unless active? && next_billing_date <= Date.current
    
    transaction do
      # Create subscription transaction
      billing_transaction = subscription_transactions.create!(
        business: business,
        tenant_customer: tenant_customer,
        amount: total_amount,
        status: :pending,
        processed_date: Date.current,
        transaction_type: 'billing'
      )
      
      # Process the subscription based on type
      success = if product_subscription?
        # Create order for product subscription
        order_service = SubscriptionOrderService.new(self)
        order_service.process_subscription!
      elsif service_subscription?
        # Create booking for service subscription
        booking_service = SubscriptionBookingService.new(self)
        booking_service.process_subscription!
      else
        false
      end
      
      if success
        billing_transaction.mark_completed!("Successfully processed #{subscription_type} subscription")
        # Update next billing date
        update!(next_billing_date: calculate_next_billing_date)
        
        # Send success notifications
        begin
          SubscriptionMailer.payment_succeeded(self).deliver_now
        rescue => e
          Rails.logger.error "[SUBSCRIPTION] Failed to send payment success email: #{e.message}"
        end
        
        begin
          if product_subscription?
            BusinessMailer.subscription_order_received(self).deliver_now
          elsif service_subscription?
            BusinessMailer.subscription_booking_received(self).deliver_now
          end
        rescue => e
          Rails.logger.error "[SUBSCRIPTION] Failed to send business notification email: #{e.message}"
        end
        
        true
      else
        billing_transaction.mark_failed!("Failed to process #{subscription_type} subscription")
        
        # Send failure notifications
        begin
          SubscriptionMailer.payment_failed(self).deliver_now
        rescue => e
          Rails.logger.error "[SUBSCRIPTION] Failed to send payment failure email: #{e.message}"
        end
        
        false
      end
    end
  rescue => e
    Rails.logger.error "[SUBSCRIPTION] Error processing billing for subscription #{id}: #{e.message}"
    # Re-raise the exception so the job can handle it and create failed_payment transactions
    raise e
  end
  
  def original_price
    item&.price&.to_f || 0.0
  end
  
  def discount_amount
    (original_price - (subscription_price&.to_f || 0.0)).round(2)
  end
  
  def savings_percentage
    return 0 if original_price.zero?
    ((discount_amount / original_price) * 100).round(1)
  end
  
  def effective_rebooking_preference
    customer_rebooking_preference.presence || 
    service&.subscription_rebooking_preference.presence || 
    business.default_service_rebooking_preference.presence || 
    'same_day_next_month'
  end
  
  def effective_out_of_stock_action
    customer_out_of_stock_preference.presence ||
    product&.subscription_out_of_stock_action.presence ||
    business.default_subscription_out_of_stock_action.presence ||
    'skip_delivery'
  end
  
  def advance_billing_date!
    new_billing_date = calculate_next_billing_date
    update!(next_billing_date: new_billing_date)
    SecureLogger.info "[SUBSCRIPTION] Advanced billing date for subscription #{id} to #{new_billing_date}"
    new_billing_date
  end
  
  def allow_customer_preferences?
    product&.allow_customer_preferences? || service&.allow_customer_preferences? || false
  end
  
  # Define ransackable attributes for ActiveAdmin
  def self.ransackable_attributes(auth_object = nil)
    %w[id business_id tenant_customer_id product_id service_id subscription_type status 
       frequency next_billing_date created_at updated_at subscription_price stripe_subscription_id
       cancelled_at preferred_staff_member_id]
  end
  
  # Define ransackable associations for ActiveAdmin
  def self.ransackable_associations(auth_object = nil)
    %w[business tenant_customer product service subscription_transactions preferred_staff_member]
  end
  
  private
  
  def must_have_product_or_service
    if service_subscription?
      if service.blank?
        errors.add(:service, 'must exist')
      end
      if product.present?
        errors.add(:product, 'must be nil for service subscriptions')
      end
    elsif product_subscription?
      if product.blank?
        errors.add(:product, 'must exist')
      end
      if service.present?
        errors.add(:service, 'must be nil for product subscriptions')
      end
    else
      if product.blank? && service.blank?
        errors.add(:base, 'Must have either a product or service')
      elsif product.present? && service.present?
        errors.add(:base, 'Cannot have both product and service')
      end
    end
  end
  
  def frequency_must_be_valid
    unless self.class.frequencies.key?(frequency)
      errors.add(:frequency, 'is not a valid frequency')
    end
  end
  
  def schedule_first_billing
    return if next_billing_date.present?
    
    # Set first billing date based on frequency
    first_billing = if weekly?
                      1.week.from_now
                    elsif monthly?
                      1.month.from_now
                    elsif quarterly?
                      3.months.from_now
                    elsif annually?
                      1.year.from_now
                    else
                      1.month.from_now
                    end
    
    update_column(:next_billing_date, first_billing.to_date)
  end
  
  def handle_status_changes
    if saved_change_to_status?
      case status
      when 'cancelled'
        # Handle cancellation logic
        Rails.logger.info "Subscription #{id} cancelled for customer #{tenant_customer_id}"
      when 'active'
        # Handle activation logic
        Rails.logger.info "Subscription #{id} activated for customer #{tenant_customer_id}"
      end
    end
  end
  
  def product_belongs_to_business
    if product && product.business_id != business_id
      errors.add(:product, 'must belong to the same business')
    end
  end
  
  def service_belongs_to_business
    if service && service.business_id != business_id
      errors.add(:service, 'must belong to the same business')
    end
  end
  
  def tenant_customer_belongs_to_business
    if tenant_customer && tenant_customer.business_id != business_id
      errors.add(:tenant_customer, 'must belong to the same business')
    end
  end
  
  def preferred_staff_member_belongs_to_business
    if preferred_staff_member && preferred_staff_member.business_id != business_id
      errors.add(:preferred_staff_member, 'must belong to the same business')
    end
  end
end 