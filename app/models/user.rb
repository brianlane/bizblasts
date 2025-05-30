# frozen_string_literal: true

# User model: Handles authentication, roles, and associations.
# Clients can associate with multiple businesses via ClientBusiness.
# Staff/Managers belong to a single business.
class User < ApplicationRecord
  # Custom exception for account deletion errors
  class AccountDeletionError < StandardError; end

  # Associations
  belongs_to :business, optional: true, inverse_of: :users
  belongs_to :staff_member, optional: true
  has_many :client_businesses, dependent: :destroy
  has_many :businesses, through: :client_businesses
  has_many :staff_assignments, dependent: :destroy
  has_many :assigned_services, through: :staff_assignments, source: :service
  has_many :staff_memberships, class_name: 'StaffMember'
  has_many :staffed_businesses, through: :staff_memberships, source: :business

  # Allow creating business via user form during sign-up
  # accepts_nested_attributes_for :business # Removed - Business creation handled explicitly in controller

  # Devise modules - Removed :validatable to use custom email uniqueness
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :confirmable # Added :confirmable for email verification

  # Callbacks
  after_update :send_domain_request_notification, if: :premium_business_confirmed_email?

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
    # Allow searching by associated business name via business_name
    %w[id email role first_name last_name active created_at updated_at business_id]
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

  # Find the StaffMember record for a specific business
  def staff_member_for(business)
    staff_memberships.find_by(business: business)
  end

  private # Ensure private keyword exists or add it if needed

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
    !persisted? || !password.nil? || !password_confirmation.nil?
  end

  def email_uniqueness_by_role_type
    return unless email.present? && email_changed? # Only validate if email is present and changed

    # Enforce global email uniqueness across all roles
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

end
