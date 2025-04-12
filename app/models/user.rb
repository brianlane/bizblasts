# frozen_string_literal: true

# User model: Handles authentication, roles, and associations.
# Clients can associate with multiple businesses via ClientBusiness.
# Staff/Managers belong to a single business.
class User < ApplicationRecord
  # Associations
  belongs_to :business, optional: true, inverse_of: :users
  belongs_to :staff_member, optional: true
  has_many :client_businesses, dependent: :destroy
  has_many :associated_businesses, through: :client_businesses, source: :business

  # Allow creating business via user form during sign-up
  # accepts_nested_attributes_for :business # Removed - Business creation handled explicitly in controller

  # Devise modules - Removed :validatable to use custom email uniqueness
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable # Removed :validatable

  # Validations
  validates :email, presence: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP } # Removed global uniqueness
  # Password validations (previously covered by :validatable)
  validates :password, presence: true, length: { minimum: 6, maximum: 128 }, confirmation: true, if: :password_required?

  validates :role, presence: true
  validate :email_uniqueness_by_role_type # Custom email validation by role type

  # Add validation for business presence for specific roles
  validates :business_id, presence: true, if: :requires_business?

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
    # Include new associations
    %w[business staff_member client_businesses associated_businesses]
  end

  # NOTE: The old :admin role (value 0) is no longer valid.
  # A data migration (Rake task) is needed to:
  # 1. Convert existing users with role 0 to role 1 (manager).
  # 2. Create ClientBusiness records for existing clients based on their current business_id.
  # 3. Set business_id to NULL for all client users after step 2.

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
