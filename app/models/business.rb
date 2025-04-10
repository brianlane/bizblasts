# frozen_string_literal: true

class Business < ApplicationRecord
  # Business represents a tenant in the multi-tenant architecture
  
  belongs_to :service_template, optional: true
  
  has_many :users, dependent: :destroy
  has_many :tenant_customers, dependent: :destroy
  has_many :services, dependent: :destroy
  has_many :staff_members, dependent: :destroy
  has_many :bookings, dependent: :destroy
  has_many :invoices, dependent: :destroy
  has_many :payments, dependent: :destroy
  has_many :marketing_campaigns, dependent: :destroy
  has_many :promotions, dependent: :destroy
  has_many :pages, dependent: :destroy
  has_many :loyalty_programs, dependent: :destroy
  
  # For Client relationships (many-to-many with User)
  has_many :client_businesses, dependent: :destroy
  has_many :clients, through: :client_businesses, source: :user
  
  validates :name, presence: true
  validates :subdomain, presence: true
  
  validate :subdomain_uniqueness, if: -> { subdomain.present? }
  
  scope :active, -> { where(active: true) }
  
  before_validation :normalize_subdomain
  
  # Find the current tenant
  def self.current
    ActsAsTenant.current_tenant
  end
  
  # Set the current tenant in ActsAsTenant
  def self.set_current_tenant(business)
    ActsAsTenant.current_tenant = business
  end
  
  def to_param
    subdomain
  end
  
  def active_services
    services.active
  end
  
  def active_staff
    staff_members.active
  end
  
  def upcoming_bookings
    bookings.upcoming
  end
  
  def today_bookings
    bookings.today
  end
  
  # Override destroy to ensure proper deletion
  def destroy
    # First remove associations that might block deletion
    self.users.update_all(business_id: nil)
    self.tenant_customers.destroy_all
    self.services.destroy_all
    self.staff_members.destroy_all
    self.bookings.destroy_all
    
    # Then proceed with actual deletion
    super
  end
  
  # Define which attributes are allowed to be searched with Ransack
  def self.ransackable_attributes(auth_object = nil)
    %w[id name subdomain time_zone active created_at updated_at]
  end
  
  # Define which associations are allowed to be searched with Ransack
  def self.ransackable_associations(auth_object = nil)
    %w[staff_members services bookings tenant_customers users clients client_businesses]
  end
  
  private
  
  def normalize_subdomain
    return if subdomain.blank?
    
    # Convert to lowercase and remove any non-alphanumeric characters
    self.subdomain = subdomain.downcase.gsub(/[^a-z0-9]/, '')
  end
  
  def subdomain_uniqueness
    return unless subdomain.present?
    
    # Skip expensive query if this is a new record with a unique subdomain
    return if new_record? && !Business.exists?(subdomain: subdomain)
    
    # For existing records, ensure no other records have the same subdomain
    if Business.where.not(id: id).exists?(subdomain: subdomain)
      errors.add(:subdomain, "has already been taken")
    end
  end
end 