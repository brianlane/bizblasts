# frozen_string_literal: true

class Business < ApplicationRecord
  # Business represents a tenant in the multi-tenant architecture
  
  # Explicitly declare the attribute type for the tier enum
  attribute :tier, :string
  
  # Enums
  enum :tier, { free: 'free', standard: 'standard', premium: 'premium' }, suffix: true
  enum :industry, {
    hair_salon: 'hair_salon',
    beauty_spa: 'beauty_spa',
    massage_therapy: 'massage_therapy',
    fitness_studio: 'fitness_studio',
    tutoring_service: 'tutoring_service',
    cleaning_service: 'cleaning_service',
    handyman_service: 'handyman_service',
    pet_grooming: 'pet_grooming',
    photography: 'photography',
    consulting: 'consulting',
    other: 'other'
  }
  enum :host_type, { subdomain: 'subdomain', custom_domain: 'custom_domain' }, prefix: true
  
  belongs_to :service_template, optional: true
  
  # Removed dependent: :destroy from all - Let DB cascade handle via FKs
  has_many :users, inverse_of: :business, validate: false
  has_many :tenant_customers
  has_many :services, dependent: :destroy
  has_many :staff_members
  has_many :bookings
  has_many :invoices
  has_many :payments
  has_many :marketing_campaigns
  has_many :promotions
  has_many :pages, dependent: :destroy
  has_many :page_sections, through: :pages
  has_many :loyalty_programs
  
  # For Client relationships (many-to-many with User)
  has_many :client_businesses
  has_many :clients, through: :client_businesses, source: :user
  
  # New association
  has_many :staff, through: :staff_members, source: :user
  
  # Validations
  validates :name, presence: true
  validates :industry, presence: true, inclusion: { in: industries.keys }
  validates :phone, presence: true # Consider adding format validation
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP } # Business contact email
  validates :address, presence: true
  validates :city, presence: true
  validates :state, presence: true
  validates :zip, presence: true # Consider adding format validation
  validates :description, presence: true
  validates :tier, presence: true, inclusion: { in: tiers.keys }
  
  # New Validations for hostname/host_type
  validates :hostname, presence: true, uniqueness: { case_sensitive: false }
  validates :host_type, presence: true, inclusion: { in: host_types.keys }

  # Subdomain format
  validates :hostname, 
            format: { 
              with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/, 
              message: "can only contain lowercase letters, numbers, and single hyphens" 
            }, 
            exclusion: { 
              in: %w(www admin mail api help support status blog), 
              message: "'%{value}' is reserved." 
            }, 
            if: :host_type_subdomain?
            
  # Custom domain format
  validates :hostname, 
            format: { 
              with: /\A(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9][a-z0-9-]{0,61}[a-z0-9]\z/, 
              message: "is not a valid domain name" 
            }, 
            if: :host_type_custom_domain?
            
  # Free tier must use subdomain
  validate :free_tier_requires_subdomain_host_type, if: :free_tier?
  
  scope :active, -> { where(active: true) }
  
  before_validation :normalize_hostname
  
  # Find the current tenant
  def self.current
    ActsAsTenant.current_tenant
  end
  
  # Set the current tenant in ActsAsTenant
  def self.set_current_tenant(business)
    ActsAsTenant.current_tenant = business
  end
  
  def to_param
    hostname
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
  
  # Define which attributes are allowed to be searched with Ransack
  def self.ransackable_attributes(auth_object = nil)
    %w[id name hostname host_type tier industry time_zone active created_at updated_at]
  end
  
  # Define which associations are allowed to be searched with Ransack
  def self.ransackable_associations(auth_object = nil)
    %w[staff_members services bookings tenant_customers users clients client_businesses]
  end
  
  private
  
  def normalize_hostname
    return if hostname.blank?
    self.hostname = hostname.downcase.strip
    # No longer perform aggressive gsub cleaning for subdomains here,
    # let the format validator handle invalid characters/structures.
  end
  
  def free_tier_requires_subdomain_host_type
    unless host_type_subdomain?
      errors.add(:host_type, "must be 'subdomain' for the Free tier")
    end
  end
end 