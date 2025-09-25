# frozen_string_literal: true

# User model: Handles authentication, roles, and associations.
# Clients can associate with multiple businesses via ClientBusiness.
# Staff/Managers belong to a single business.
class User < ApplicationRecord
  include UnsubscribeTokenGenerator
  
  # Custom exception for account deletion errors
  class AccountDeletionError < StandardError; end
  
  # Virtual attribute for notification consent checkbox in registration
  attr_accessor :bizblasts_notification_consent

  # Associations
  belongs_to :business, optional: true, inverse_of: :users
  belongs_to :staff_member, optional: true
  has_many :client_businesses, dependent: :destroy
  has_many :businesses, through: :client_businesses
  has_many :staff_assignments, dependent: :destroy
  has_many :assigned_services, through: :staff_assignments, source: :service
  has_many :staff_memberships, class_name: 'StaffMember', foreign_key: 'user_id', dependent: :destroy
  has_many :businesses_as_staff, through: :staff_memberships, source: :business
  has_many :policy_acceptances, dependent: :destroy
  # Track which setup reminder tasks the user has dismissed
  has_many :setup_reminder_dismissals, dependent: :destroy
  has_many :user_sidebar_items, dependent: :destroy
  
  # Referral system associations
  has_many :referrals_made, class_name: 'Referral', foreign_key: 'referrer_id', dependent: :destroy
  
  # Devise modules - Removed :validatable to use custom email uniqueness
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :confirmable, :trackable, :magic_link_authenticatable # Added :confirmable for email verification and :trackable for login tracking

  # Callbacks
  after_update :send_domain_request_notification, if: :premium_business_confirmed_email?
  after_update :clear_tenant_customer_cache, if: :saved_change_to_email?
  after_update :sync_email_to_tenant_customers, if: -> { client? && saved_change_to_email? && confirmed? }
  after_update :sync_phone_to_tenant_customers, if: -> { client? && saved_change_to_phone? && phone.present? }
  after_create :generate_unsubscribe_token
  after_create :set_default_notification_preferences

  # Validations
  validates :email, presence: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP } # Removed global uniqueness
  # Password validations (previously covered by :validatable)
  validates :password, presence: true, length: { minimum: 6, maximum: 128 }, confirmation: true, if: :password_required?

  validates :role, presence: true
  validate :email_uniqueness_by_role_type # Custom email validation by role type

  # Add validation for business presence for specific roles
  validates :business_id, presence: true, if: :requires_business?

  # Add first_name and last_name attributes
  validates :first_name, presence: true
  validates :last_name, presence: true

  # Roles Enum - :admin removed, default changed to :client
  enum :role, {
    manager: 1,
    staff: 2,
    client: 3
  }, default: :client

  # Scopes
  scope :active, -> { where(active: true) }
  scope :business_users, -> { where(role: [:manager, :staff]) }
  scope :clients, -> { where(role: :client) }
  scope :subscribed_to_emails, -> { where(unsubscribed_at: nil) }
  scope :unsubscribed_from_emails, -> { where.not(unsubscribed_at: nil) }

  # Methods
  def active_for_authentication?
    super && active?
  end

  # Check if user role requires belonging to a business
  def requires_business?
    manager? || staff?
  end

  def full_name
    [first_name, last_name].compact.join(' ').presence || email
  end

  # Account deletion methods
  def can_delete_account?
    result = {
      can_delete: true,
      restrictions: [],
      warnings: []
    }

    case role
    when 'client'
      # Clients can always delete their accounts
      add_client_warnings(result)
    when 'staff'
      add_staff_warnings(result)
    when 'manager'
      add_manager_restrictions_and_warnings(result)
    end

    result
  end

  def destroy_account(options = {})
    delete_business = options[:delete_business] || false
    
    case role
    when 'client'
      destroy_client_account
    when 'staff'
      destroy_staff_account
    when 'manager'
      destroy_manager_account(delete_business)
    end
  end

  # Ransackable Attributes & Associations
  def self.ransackable_attributes(auth_object = nil)
    # Allow searching by associated business name via business_name, including login tracking fields
    %w[id email role first_name last_name active created_at updated_at business_id sign_in_count current_sign_in_at last_sign_in_at]
  end

  def self.ransackable_associations(auth_object = nil)
    # Include new associations, correcting the name
    %w[business staff_member client_businesses businesses staff_assignments assigned_services]
  end

  # NOTE: The old :admin role (value 0) is no longer valid.
  # A data migration (Rake task) is needed to:
  # 1. Convert existing users with role 0 to role 1 (manager).
  # 2. Create ClientBusiness records for existing clients based on their current business_id.
  # 3. Set business_id to NULL for all client users after step 2.

  # Explicitly public role check methods
  public

  def manager?
    role == 'manager'
  end

  def staff?
    role == 'staff'
  end
  
  def client?
    role == 'client'
  end

  # Platform admins are handled by AdminUser model
  def admin?
    false
  end

  def has_any_role?(*roles_to_check)
    # Convert symbols to strings for comparison with the string value from the enum
    roles_to_check.any? { |role_sym| self.role == role_sym.to_s }
  end

  # Check if user is a business manager for a specific business
  def business_manager?(business)
    manager? && self.business_id == business.id
  end

  # Booking policy override capabilities
  def can_override_booking_policies?
    manager? || staff?
  end

  # Check if user can cancel a specific booking (considering policies and role)
  def can_cancel_booking?(booking)
    # Business managers and staff can always cancel bookings for their business
    if (manager? || staff?) && business_id == booking.business_id
      return true
    end
    
    # For client users, check the booking policy
    if client?
      policy = booking.business.booking_policy
      return policy&.user_can_cancel?(self, booking) || false # Default to false if no policy to ensure safety
    end
    
    false
  end

  # Find the StaffMember record for a specific business
  def staff_member_for(business)
    staff_memberships.find_by(business: business)
  end

  # Policy acceptance methods
  def needs_policy_acceptance?
    requires_policy_acceptance? || missing_required_policies.any?
  end
  
  def missing_required_policies
    # Cache during request cycle, but not across requests in test environment
    if Rails.env.test?
      # Always calculate fresh in tests for immediate feedback
      calculate_missing_required_policies
    else
      # Use instance variable caching for production/development
      @missing_required_policies ||= calculate_missing_required_policies
    end
  end
  
  def mark_policies_accepted!
    # Clear all policy-related caches
    clear_policy_caches
    update!(requires_policy_acceptance: false, last_policy_notification_at: Time.current)
  end

  # Cache tenant customer IDs for efficient cross-business user lookups
  def tenant_customer_ids
    return [] unless client?
    @tenant_customer_ids ||= Rails.cache.fetch("user_#{id}_tenant_customers", expires_in: 30.minutes) do
      TenantCustomer.where(email: email).pluck(:id)
    end
  end

  # Clear tenant customer cache when email changes
  def clear_tenant_customer_cache
    Rails.cache.delete("user_#{id}_tenant_customers")
    @tenant_customer_ids = nil
  end
  
  # Get linked tenant customer for a specific business
  def tenant_customer_for(business)
    return nil unless client?
    TenantCustomer.find_by(user_id: id, business: business)
  end
  
  # Get all linked tenant customers
  def linked_tenant_customers
    return TenantCustomer.none unless client?
    TenantCustomer.where(user_id: id)
  end
  
  # Clear all policy-related caches
  def clear_policy_caches
    @missing_required_policies = nil
    
    # Clear individual policy acceptance caches
    %w[terms_of_service privacy_policy acceptable_use_policy return_policy].each do |policy_type|
      Rails.cache.delete("user_#{id}_policy_acceptance_#{policy_type}")
    end
    
    # Clear policy status response cache
    Rails.cache.delete("policy_status_response_#{id}")
    Rails.cache.delete("policy_status_check_#{id}")
  end

  # Returns true if the user can receive a given type of email (e.g., :marketing, :blog, :booking, etc.)
  def can_receive_email?(type)
    return true if type == :transactional # Always allow transactional emails
    return false if unsubscribed_from_emails?

    # Map type to notification_preferences key(s)
    key_map = {
      marketing: %w[email_marketing_notifications email_promotional_offers email_marketing_updates email_promotions],
      blog: %w[email_blog_notifications email_blog_updates blog_post_notifications],
      booking: %w[email_booking_notifications email_booking_confirmation email_booking_updates],
      order: %w[email_order_notifications email_order_updates],
      payment: %w[email_payment_notifications email_payment_confirmations],
      customer: %w[email_customer_notifications],
      system: %w[system_notifications],
      subscription: %w[email_subscription_notifications]
    }
    keys = key_map[type.to_sym] || []
    return true if keys.empty? # If unknown type, default to allow
    
    # If no notification preferences are set, default to true
    return true if notification_preferences.nil? || notification_preferences.empty?
    
    # Check if ANY of the relevant keys are enabled (not explicitly set to false)
    # This allows users to receive emails from a category if they have at least one preference enabled
    # Treat nil as enabled (default) to maintain backward compatibility
    keys.any? { |k| notification_preferences[k] != false }
  end

  # SMS opt-in methods for User model (business users)
  def can_receive_sms?(type)
    return false unless phone.present? # Must have phone number
    return false unless business&.sms_enabled? # Business must have SMS enabled
    return false unless phone_opt_in? # Must be opted in

    # Users with business roles can receive business notifications
    case type.to_sym
    when :marketing
      phone_opt_in? && business&.sms_marketing_enabled? && !phone_marketing_opt_out?
    when :booking, :order, :payment, :reminder, :system, :subscription, :customer
      phone_opt_in?
    else
      phone_opt_in?
    end
  end

  def phone_opt_in?
    # For User model, check if phone_opt_in attribute exists and is true
    respond_to?(:phone_opt_in) ? phone_opt_in : false
  end

  def phone_marketing_opt_out?
    # For User model, check if phone_marketing_opt_out attribute exists
    respond_to?(:phone_marketing_opt_out) ? phone_marketing_opt_out : false
  end

  # Opt user into SMS notifications
  def opt_into_sms!
    update!(
      phone_opt_in: true,
      phone_opt_in_at: Time.current
    )
  end

  # Opt user out of SMS notifications  
  def opt_out_of_sms!
    update!(
      phone_opt_in: false,
      phone_opt_in_at: nil
    )
  end

  # Opt user out of marketing SMS only
  def opt_out_of_sms_marketing!
    update!(phone_marketing_opt_out: true)
  end

  def unsubscribed_from_emails?
    # Check if globally unsubscribed via button (unsubscribed_at set)
    return true if unsubscribed_at.present?
    
    # Check if all email notification preferences are false
    return false if notification_preferences.nil? || notification_preferences.empty?
    
    email_preferences = %w[
      email_booking_notifications email_customer_notifications email_payment_notifications 
      email_subscription_notifications email_marketing_notifications email_blog_notifications
      email_system_notifications email_marketing_updates email_blog_updates
    ]
    
    email_preferences.all? { |pref| notification_preferences[pref] == false }
  end

  def subscribed_to_emails?
    !unsubscribed_from_emails?
  end

  def sidebar_items_config
    if user_sidebar_items.exists?
      defaults = UserSidebarItem.default_items_for(self).index_by { |item| item[:key] }
      visible_items = user_sidebar_items.order(:position).select { |item| item.visible }
      return [] if user_sidebar_items.count > 0 && visible_items.empty?
      visible_items.map do |item|
        label = defaults[item.item_key]&.dig(:label) || item.item_key.humanize
        OpenStruct.new(item_key: item.item_key, label: label, position: item.position, visible: item.visible)
      end
    else
      UserSidebarItem.default_items_for(self).map.with_index do |item, idx|
        OpenStruct.new(item_key: item[:key], label: item[:label], position: idx, visible: true)
      end
    end
  end

  # Unsubscribe system methods

  def unsubscribe_from_emails!
    update!(
      unsubscribed_at: Time.current,
      email_marketing_opt_out: true
    )
    # Update notification preferences to disable email notifications
    update_notification_preferences_for_unsubscribe
  end

  def resubscribe_to_emails!
    update!(
      unsubscribed_at: nil,
      email_marketing_opt_out: false
    )
    regenerate_unsubscribe_token
  end

  def update_notification_preferences_for_unsubscribe
    return unless notification_preferences.present?
    
    # Disable all email-related notification preferences
    updated_preferences = notification_preferences.dup
    email_preferences = %w[
      email_booking_confirmation
      email_booking_updates
      email_order_updates
      email_payment_confirmations
      email_promotions
      email_blog_updates
      email_booking_notifications
      email_customer_notifications
      email_payment_notifications
      email_subscription_notifications
      email_marketing_notifications
      email_blog_notifications
      email_system_notifications
      email_marketing_updates
    ]
    
    email_preferences.each do |pref|
      updated_preferences[pref] = false
    end
    
    update_column(:notification_preferences, updated_preferences)
  end

  private # Ensure private keyword exists or add it if needed

  def set_default_notification_preferences
    # Only set defaults if notification_preferences is nil or empty
    return if notification_preferences.present?
    
    # Check if user consented to notifications during registration
    # If bizblasts_notification_consent is explicitly false (unchecked), set all notifications to false
    # If not provided or true (checked), enable all notifications
    consent_given = bizblasts_notification_consent != false && bizblasts_notification_consent != '0'
    
    default_preferences = {
      # Booking & Service Notifications
      email_booking_confirmation: consent_given,
      sms_booking_reminder: consent_given,
      email_booking_updates: consent_given,
      
      # Order & Product Notifications
      email_order_updates: consent_given,
      sms_order_updates: consent_given,
      email_payment_confirmations: consent_given,
      
      # Marketing & Promotional
      email_promotions: consent_given,
      email_blog_updates: consent_given,
      sms_promotions: consent_given,
      
      # Additional notification types from the system
      email_booking_notifications: consent_given,
      email_customer_notifications: consent_given,
      email_payment_notifications: consent_given,
      email_subscription_notifications: consent_given,
      email_marketing_notifications: consent_given,
      email_blog_notifications: consent_given,
      email_system_notifications: consent_given,
      email_marketing_updates: consent_given
    }
    
    # Use update_attribute to ensure the change persists even in CI environments
    if update_attribute(:notification_preferences, default_preferences)
      Rails.logger.info "[USER] Set default notification preferences for User ##{id} (#{email}) - consent: #{consent_given}"
    else
      Rails.logger.error "[USER] Failed to set default notification preferences for User ##{id} (#{email})"
    end
  end

  def add_client_warnings(result)
    if client_businesses.any?
      result[:warnings] << "You will be removed from #{client_businesses.count} business relationship(s)"
    end
    
    # Count associated tenant customers (bookings/orders tied to this user's email)
    tenant_customer_count = TenantCustomer.where(email: email).count
    if tenant_customer_count > 0
      result[:warnings] << "Your booking and order history will not be preserved"
    end
  end

  def add_staff_warnings(result)
    return unless business.present?

    # Check for future bookings
    future_bookings = Booking.joins(:staff_member)
                            .where(staff_members: { user_id: id })
                            .where('start_time > ?', Time.current)
    
    if future_bookings.any?
      result[:warnings] << "You have #{future_bookings.count} future booking(s) that will be reassigned or cancelled"
    end

    # Check for assigned services
    if assigned_services.any?
      result[:warnings] << "You are assigned to #{assigned_services.count} service(s)"
    end
  end

  def add_manager_restrictions_and_warnings(result)
    return unless business.present?

    other_managers = business.users.where(role: 'manager').where.not(id: id)
    other_users = business.users.where.not(id: id)

    if other_managers.empty?
      if other_users.empty?
        # Sole user - can delete but must delete business too
        result[:warnings] << "You are the sole user of this business. This will also delete the business and all its data."
      else
        # Sole manager but has staff - cannot delete
        result[:can_delete] = false
        result[:restrictions] << "Cannot delete the sole manager account while staff members exist. Please transfer management rights first."
      end
    else
      # Other managers exist - can delete safely
      result[:warnings] << "Management responsibilities will transfer to other managers"
    end

    # Add business data warnings for sole user scenario
    if other_users.empty?
      add_business_deletion_warnings(result)
    end
  end

  def add_business_deletion_warnings(result)
    return unless business.present?

    data_counts = {
      services: business.services.count,
      staff_members: business.staff_members.count,
      customers: business.tenant_customers.count,
      bookings: business.bookings.count,
      orders: business.orders.count,
      products: business.products.count
    }

    warnings = []
    data_counts.each do |type, count|
      warnings << "#{count} #{type.to_s.humanize.downcase}" if count > 0
    end

    if warnings.any?
      result[:warnings] << "Deleting the business will permanently remove: #{warnings.join(', ')}"
    end
  end

  def destroy_client_account
    # Use transaction to ensure atomicity
    ActiveRecord::Base.transaction do
      # Client businesses will be deleted by dependent: :destroy
      # No foreign key constraints to worry about for clients
      destroy!
    end

    { deleted: true, business_deleted: false }
  end

  def destroy_staff_account
    ActiveRecord::Base.transaction do
      # Handle foreign key constraints
      
      # Find staff_member records where this user is the associated user
      staff_members_to_delete = StaffMember.where(user_id: id)
      
      staff_members_to_delete.each do |staff_member_record|
        # Nullify bookings that reference this staff member before deleting
        staff_member_record.bookings.update_all(staff_member_id: nil)
        # Nullify the user association to prevent infinite loops, then delete
        staff_member_record.update_column(:user_id, nil)
        staff_member_record.destroy!
      end

      # Staff assignments will be deleted by dependent: :destroy
      
      destroy!
    end

    { deleted: true, business_deleted: false }
  end

  def destroy_manager_account(delete_business = false)
    return unless business.present?

    other_managers = business.users.where(role: 'manager').where.not(id: id)
    other_users = business.users.where.not(id: id)

    # Validate deletion is allowed
    if other_managers.empty? && other_users.any?
      raise AccountDeletionError, "Cannot delete the sole manager account while staff members exist"
    end

    # If sole user and delete_business not confirmed, raise error
    if other_users.empty? && !delete_business
      raise AccountDeletionError, "You are the sole user of this business. This will also delete the business. Please confirm business deletion."
    end

    ActiveRecord::Base.transaction do
      business_deleted = false

      if other_users.empty? && delete_business
        # Delete the entire business - foreign keys will cascade appropriately
        business.destroy!
        business_deleted = true
      else
        # Handle manager-specific cleanup
        
        # Find staff_member records where this user is the associated user
        staff_members_to_delete = StaffMember.where(user_id: id)
        
        staff_members_to_delete.each do |staff_member_record|
          # Nullify bookings that reference this staff member before deleting
          staff_member_record.bookings.update_all(staff_member_id: nil)
          # Nullify the user association to prevent infinite loops, then delete
          staff_member_record.update_column(:user_id, nil)
          staff_member_record.destroy!
        end

        # Staff assignments will be deleted by dependent: :destroy
      end

      # Delete the user
      destroy!

      { deleted: true, business_deleted: business_deleted }
    end
  end

  # Check if this is a premium business user who just confirmed their email
  def premium_business_confirmed_email?
    return false unless confirmed_at_changed? && confirmed_at.present?
    return false unless business.present? && business.premium_tier?
    return false unless business.host_type_custom_domain?
    true
  end

  # Send domain request notification email
  def send_domain_request_notification
    begin
      BusinessMailer.domain_request_notification(self).deliver_later
      Rails.logger.info "[EMAIL] Sent domain request notification for User ##{id} - Business: #{business.name}"
    rescue => e
      Rails.logger.error "[EMAIL] Failed to send domain request notification for User ##{id}: #{e.message}"
    end
  end

  # Helper method for conditional password validation (mimics Devise behavior)
  def password_required?
    !persisted? || password.present? || password_confirmation.present?
  end

  def email_uniqueness_by_role_type
    return unless email.present? && email_changed? # Only validate if email is present and changed

    # Enforce global email uniqueness across all users
    if User.where.not(id: id).exists?(email: email)
      errors.add(:email, :taken)
    end

    # Removed role-specific checks
    # # Check uniqueness for clients
    # if client?
    #   if User.where.not(id: id).clients.exists?(email: email)
    #     errors.add(:email, "has already been taken by another client") # Custom message
    #   end
    # # Check uniqueness for business users (managers/staff) - across all businesses
    # elsif manager? || staff?
    #   if User.where.not(id: id).business_users.exists?(email: email)
    #     # Match spec expectation
    #     errors.add(:email, "has already been taken by another business owner or staff member")
    #   end
    # end
  end

  def calculate_missing_required_policies
    required_policies = case role
    when 'client'
      %w[privacy_policy terms_of_service acceptable_use_policy]
    when 'manager', 'staff'
      %w[terms_of_service privacy_policy acceptable_use_policy return_policy]
    else
      %w[privacy_policy terms_of_service acceptable_use_policy]
    end
    
    required_policies.reject do |policy_type|
      current_version = PolicyVersion.current_version(policy_type)
      next true unless current_version # Skip if no current version
      
      PolicyAcceptance.has_accepted_policy?(self, policy_type, current_version.version)
    end
  end
  
  # Sync email changes to linked tenant customers (after email confirmation)
  def sync_email_to_tenant_customers
    return unless client?
    
    old_email = email_before_last_save
    new_email = email.downcase.strip
    
    Rails.logger.info "[USER] Syncing email change from #{old_email} to #{new_email} for user #{id}"                                                           
    
    # Use transaction to ensure atomicity and handle uniqueness conflicts
    ActiveRecord::Base.transaction do
      linked = linked_tenant_customers.lock

      # Check for any conflicting customer in the same businesses
      business_ids = linked.pluck(:business_id)
      conflicts = TenantCustomer.where(business_id: business_ids, email: new_email)
                                 .where.not(user_id: id)

      if conflicts.exists?
        conflict = conflicts.first
        Rails.logger.error "[USER] Email sync conflict for user #{id} -> business #{conflict.business_id} existing user #{conflict.user_id}"
        raise EmailConflictError.new(
          "This email is already associated with another customer in one of your businesses.",
          email: new_email,
          business_id: conflict.business_id,
          existing_user_id: conflict.user_id,
          attempted_user_id: id
        )
      end

      # Update all linked tenant customers safely
      updated_count = linked.update_all(email: new_email)
      Rails.logger.info "[USER] Updated #{updated_count} tenant customer records with new email"

      clear_tenant_customer_cache
    end
  rescue => e
    Rails.logger.error "[USER] Failed to sync email to tenant customers: #{e.message}"
    # Re-raise to ensure the error is handled by the caller
    raise e
  end
  
  # Sync phone changes to linked tenant customers
  def sync_phone_to_tenant_customers
    return unless client?
    
    Rails.logger.info "[USER] Syncing phone number to tenant customers for user #{id}"                                                                         
    
    # Use transaction to ensure atomicity
    ActiveRecord::Base.transaction do
      # Update phone for all linked customers where phone is blank or different
      linked_tenant_customers.each do |customer|
        updates = {}
        
        # Update phone if customer doesn't have one or if different
        if customer.phone.blank? || customer.phone != phone
          updates[:phone] = phone
          
          # Set opt-in if user has opted in and customer hasn't
          if respond_to?(:phone_opt_in?) && phone_opt_in? && !customer.phone_opt_in?                                                                             
            updates[:phone_opt_in] = true
            updates[:phone_opt_in_at] = respond_to?(:phone_opt_in_at) ? phone_opt_in_at : Time.current                                                           
          end
        end
        
        if updates.any?
          customer.update!(updates)
          Rails.logger.info "[USER] Updated tenant customer #{customer.id} with phone data"                                                                      
        end
      end
    end
  rescue => e
    Rails.logger.error "[USER] Failed to sync phone to tenant customers: #{e.message}"
    # Re-raise to ensure the error is handled by the caller
    raise e
  end

end
