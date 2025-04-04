# frozen_string_literal: true

# User model that handles authentication and user management
# Uses Devise for authentication and acts_as_tenant for multi-tenancy
class User < ApplicationRecord
  include TenantScoped
  
  acts_as_tenant(:business)
  belongs_to :business
  belongs_to :staff_member, optional: true

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # Override Devise's email uniqueness validator 
  validates :email, presence: true, 
                    format: { with: URI::MailTo::EMAIL_REGEXP },
                    uniqueness: { scope: :business_id, case_sensitive: false }
  
  # Ensure business_id is set before validation
  before_validation :ensure_business_id_set
  
  validates :role, presence: true
  
  enum :role, {
    admin: 0,
    manager: 1,
    staff: 2,
    client: 3
  }
  
  scope :active, -> { where(active: true) }
  scope :staff_users, -> { where(role: [:admin, :manager, :staff]) }
  
  def active_for_authentication?
    super && active?
  end
  
  def staff?
    admin? || manager? || self.role == 'staff'
  end
  
  def full_name
    email
  end
  
  # Override Devise's email uniqueness validation
  def email_changed?
    false
  end
  
  def will_save_change_to_email?
    false
  end
  
  # Define which attributes are allowed to be searched with Ransack
  def self.ransackable_attributes(auth_object = nil)
    %w[id email role created_at updated_at business_id]
  end
  
  # Define which associations are allowed to be searched with Ransack
  def self.ransackable_associations(auth_object = nil)
    %w[business]
  end
  
  private
  
  def ensure_business_id_set
    self.business_id = ActsAsTenant.current_tenant&.id if business_id.nil? && ActsAsTenant.current_tenant.present?
  end
end
