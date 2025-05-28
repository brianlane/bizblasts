# frozen_string_literal: true

# User model: Handles authentication, roles, and associations.
# Clients can associate with multiple businesses via ClientBusiness.
# Staff/Managers belong to a single business.
class User < ApplicationRecord
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
