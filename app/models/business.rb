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
  has_many :products, dependent: :destroy
  has_many :orders, dependent: :destroy
  has_many :categories, dependent: :destroy
  has_many :shipping_methods, dependent: :destroy
  has_many :tax_rates, dependent: :destroy
  
  # For Client relationships (many-to-many with User)
  has_many :client_businesses
  has_many :clients, through: :client_businesses, source: :user
  
  # New association
  has_many :staff, through: :staff_members, source: :user
  
  # New association for BookingPolicy
  has_one :booking_policy, dependent: :destroy
  
  # New associations for Modules 5 and 6
  has_many :notification_templates, dependent: :destroy
  has_many :integration_credentials, dependent: :destroy
  has_many :locations, dependent: :destroy
  has_one :subscription, dependent: :destroy # Added for Module 7
  has_many :integrations, dependent: :destroy # Added for Module 9
  
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
  before_validation :ensure_hours_is_hash
  before_destroy :orphan_all_bookings
  after_save :sync_hours_with_default_location, if: :saved_change_to_hours?
  
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
  
  # Get the default tax rate for this business
  def default_tax_rate
    tax_rates.first
  end
  
  # Get the default location for this business
  def default_location
    locations.first
  end
  
  # Define which attributes are allowed to be searched with Ransack
  def self.ransackable_attributes(auth_object = nil)
    %w[id name hostname host_type tier industry time_zone active created_at updated_at stripe_customer_id]
  end
  
  # Define which associations are allowed to be searched with Ransack
  def self.ransackable_associations(auth_object = nil)
    %w[staff_members services bookings tenant_customers users clients client_businesses subscription integrations]
  end
  
  # Method to get the full URL for this business
  def full_url(path = nil)
    # Determine host based on environment and host_type
    host = if Rails.env.development?
      # Development: use lvh.me with subdomain
      "#{hostname}.lvh.me"
    elsif host_type_custom_domain?
      # Custom domain: use full hostname
      hostname
    else
      # Subdomain in other envs: append main domain
      "#{hostname}.bizblasts.com"
    end

    # Determine protocol
    protocol = Rails.env.development? ? 'http://' : 'https://'

    # Determine port in development from action_mailer default_url_options
    port = ''
    if Rails.env.development?
      default_opts = Rails.application.config.action_mailer.default_url_options rescue {}
      port = ":#{default_opts[:port]}" if default_opts[:port].present?
    end

    # Build URL
    url = "#{protocol}#{host}#{port}"
    url += path.to_s if path.present?
    url
  end

  
  has_one_attached :logo
  
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
  
  # Sync business hours with the default location
  def sync_hours_with_default_location
    return unless default_location.present?
    
    # If the business saved with updated hours, update the default location's hours
    if hours.present?
      default_location.update_columns(hours: hours)
      Rails.logger.info "[BUSINESS] Synced hours from business to default location ##{default_location.id}"
    end
  end
  
  # Ensure hours is stored as a hash
  def ensure_hours_is_hash
    if self.hours.is_a?(String)
      begin
        self.hours = JSON.parse(self.hours)
      rescue JSON::ParserError => e
        Rails.logger.error "[BUSINESS] Error parsing hours JSON: #{e.message}"
        # Default to empty hash if parsing fails
        self.hours = {} unless self.hours.is_a?(Hash)
      end
    end
    
    # Ensure hours is a hash
    self.hours = {} unless self.hours.is_a?(Hash)
  end
  
  def orphan_all_bookings
    ActsAsTenant.without_tenant do
      # Mark all bookings as business_deleted and remove associations
      bookings.find_each do |booking|
        booking.mark_business_deleted!
      end
      
      # Mark all orders as business_deleted and remove associations
      orders.find_each do |order|
        order.mark_business_deleted!
      end
      
      # Mark all invoices as business_deleted and remove associations
      invoices.find_each do |invoice|
        invoice.mark_business_deleted!
      end
      
      # Mark all payments as business_deleted and remove associations
      payments.find_each do |payment|
        payment.mark_business_deleted!
      end
    end
  end
end 