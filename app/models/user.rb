# frozen_string_literal: true

# User model: Handles authentication, roles, and associations.
# Clients can associate with multiple businesses via ClientBusiness.
# Staff/Managers belong to a single business.
class User < ApplicationRecord
  # Associations
  belongs_to :business, optional: true # Required only for manager/staff roles
  belongs_to :staff_member, optional: true
  has_many :client_businesses, dependent: :destroy
  has_many :associated_businesses, through: :client_businesses, source: :business

  # Devise modules
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # Validations
  validates :email, presence: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP },
                    uniqueness: { case_sensitive: false } # Global uniqueness
  validates :role, presence: true
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

end
