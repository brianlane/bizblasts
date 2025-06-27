# frozen_string_literal: true

class Business < ApplicationRecord
  # Business represents a tenant in the multi-tenant architecture
  
  # Define the comprehensive list of industries based on showcase examples
  SHOWCASE_INDUSTRY_MAPPINGS = {
    # Services
    hair_salons: "Hair Salons",
    massage_therapy: "Massage Therapy",
    pet_grooming: "Pet Grooming",
    auto_repair: "Auto Repair",
    hvac_services: "HVAC Services",
    plumbing: "Plumbing",
    landscaping: "Landscaping",
    pool_services: "Pool Services",
    cleaning_services: "Cleaning Services",
    tutoring: "Tutoring",
    personal_training: "Personal Training",
    photography: "Photography",
    web_design: "Web Design",
    consulting: "Consulting",
    accounting: "Accounting",
    legal_services: "Legal Services",
    dental_care: "Dental Care",
    veterinary: "Veterinary",
    handyman_service: "Handyman Service",
    painting: "Painting",
    roofing: "Roofing",
    carpet_cleaning: "Carpet Cleaning",
    pest_control: "Pest Control",
    beauty_spa: "Beauty Spa",
    moving_services: "Moving Services",
    catering: "Catering",
    dj_services: "DJ Services",
    event_planning: "Event Planning",
    tax_preparation: "Tax Preparation",
    it_support: "IT Support",

    # Experiences
    yoga_classes: "Yoga Classes",
    escape_rooms: "Escape Rooms",
    wine_tasting: "Wine Tasting",
    cooking_classes: "Cooking Classes",
    art_studios: "Art Studios",
    dance_studios: "Dance Studios",
    music_lessons: "Music Lessons",
    adventure_tours: "Adventure Tours",
    boat_charters: "Boat Charters",
    helicopter_tours: "Helicopter Tours",
    food_tours: "Food Tours",
    ghost_tours: "Ghost Tours",
    museums: "Museums",
    aquariums: "Aquariums",
    theme_parks: "Theme Parks",
    zip_lines: "Zip Lines",
    paintball: "Paintball",
    laser_tag: "Laser Tag",
    bowling_alleys: "Bowling Alleys",
    mini_golf: "Mini Golf",
    go_kart_racing: "Go-Kart Racing",
    arcades: "Arcades",
    comedy_clubs: "Comedy Clubs",
    theater_shows: "Theater Shows",
    concerts: "Concerts",
    festivals: "Festivals",
    workshops: "Workshops",
    seminars: "Seminars",
    retreats: "Retreats",
    spa_days: "Spa Days",

    # Products
    boutiques: "Boutiques",
    jewelry_stores: "Jewelry Stores",
    electronics: "Electronics",
    bookstores: "Bookstores",
    art_galleries: "Art Galleries",
    craft_stores: "Craft Stores",
    antique_shops: "Antique Shops",
    toy_stores: "Toy Stores",
    sports_equipment: "Sports Equipment",
    outdoor_gear: "Outdoor Gear",
    home_decor: "Home Decor",
    furniture_stores: "Furniture Stores",
    bakeries: "Bakeries",
    coffee_shops: "Coffee Shops",
    wine_shops: "Wine Shops",
    specialty_foods: "Specialty Foods",
    cosmetics: "Cosmetics",
    perfume_shops: "Perfume Shops",
    pet_supplies: "Pet Supplies",
    plant_nurseries: "Plant Nurseries",
    garden_centers: "Garden Centers",
    hardware_stores: "Hardware Stores",
    music_stores: "Music Stores",
    gift_shops: "Gift Shops",
    souvenir_shops: "Souvenir Shops",
    thrift_stores: "Thrift Stores",
    clothing: "Clothing",
    local_artisans: "Local Artisans",
    handmade_goods: "Handmade Goods",
    farmers_markets: "Farmers Markets",

    # Other
    other: "Other"
  }.freeze
  
  # Explicitly declare the attribute type for the tier enum
  attribute :tier, :string
  
  # Enums
  enum :tier, { free: 'free', standard: 'standard', premium: 'premium' }, suffix: true
  enum :industry, SHOWCASE_INDUSTRY_MAPPINGS
  enum :host_type, { subdomain: 'subdomain', custom_domain: 'custom_domain' }, prefix: true
  
  belongs_to :service_template, optional: true
  
  # Removed dependent: :destroy from all - Let DB cascade handle via FKs
  has_many :users, inverse_of: :business, dependent: :destroy, validate: false
  has_many :tenant_customers
  has_many :services, dependent: :destroy
  has_many :staff_members
  has_many :bookings  # Orphaned, not deleted
  has_many :invoices  # Orphaned, not deleted
  has_many :payments  # Orphaned, not deleted
  has_many :marketing_campaigns
  has_many :promotions
  has_many :pages, dependent: :destroy
  has_many :page_sections, through: :pages
  has_many :loyalty_programs
  has_many :products, dependent: :destroy
  has_many :orders  # Orphaned, not deleted
  has_many :shipping_methods, dependent: :destroy
  has_many :tax_rates, dependent: :destroy
  
  # Referral and Loyalty system associations
  has_one :referral_program, dependent: :destroy
  has_many :referrals, dependent: :destroy
  has_many :loyalty_transactions, dependent: :destroy
  has_many :loyalty_redemptions, dependent: :destroy
  has_many :discount_codes, dependent: :destroy
  
  # Customer subscription associations
  has_many :customer_subscriptions, dependent: :destroy
  has_many :subscription_transactions, dependent: :destroy
  
  # Platform (BizBlasts) referral and loyalty associations
  has_many :platform_referrals_made, class_name: 'PlatformReferral', foreign_key: 'referrer_business_id', dependent: :destroy
  has_many :platform_referrals_received, class_name: 'PlatformReferral', foreign_key: 'referred_business_id', dependent: :destroy
  has_many :platform_loyalty_transactions, dependent: :destroy
  has_many :platform_discount_codes, dependent: :destroy
  
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
  
  # Tips associations
  has_many :tips, dependent: :destroy
  has_one :tip_configuration, dependent: :destroy
  
  # Website customization associations
  has_many :website_themes, dependent: :destroy
  has_one :active_website_theme, -> { where(active: true) }, class_name: 'WebsiteTheme'
  
  # Tip configuration helper methods
  def tip_configuration_or_default
    tip_configuration || build_tip_configuration
  end
  
  def ensure_tip_configuration!
    return tip_configuration if tip_configuration.present?
    create_tip_configuration!
  end
  
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
  before_destroy :orphan_all_bookings, prepend: true
  after_save :sync_hours_with_default_location, if: :saved_change_to_hours?
  after_update :handle_loyalty_program_disabled, if: :saved_change_to_loyalty_program_enabled?
  
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
  
  # Referral and Loyalty program methods
  def referral_program_active?
    referral_program_enabled? && referral_program&.active?
  end
  
  def loyalty_program_active?
    loyalty_program_enabled?
  end
  
  def loyalty_program_enabled?
    read_attribute(:loyalty_program_enabled) || false
  end
  
  def calculate_loyalty_points(amount_spent, service: nil, product: nil)
    return 0 unless loyalty_program_active?
    
    points = 0
    
    # Points per dollar spent
    points += (amount_spent * points_per_dollar).to_i if amount_spent.present?
    
    # Fixed points per service
    points += points_per_service.to_i if service.present? && points_per_service > 0
    
    # Fixed points per product  
    points += points_per_product.to_i if product.present? && points_per_product > 0
    
    points
  end
  
  def ensure_referral_program!
    return referral_program if referral_program.present?
    
    create_referral_program!(
      active: true,
      referrer_reward_type: 'points',
      referrer_reward_value: 100,
      referral_code_discount_amount: 10.0,
      min_purchase_amount: 0.0
    )
  end

  # Subscription methods
  def subscription_discount_enabled?
    # For now, enable subscriptions for all businesses
    # This could be enhanced to check a business setting or tier
    true
  end

  def subscription_discount_percentage
    # Default subscription discount percentage
    # This could be made configurable per business
    10.0
  end
  
  def default_service_rebooking_preference
    'same_day_next_month'
  end
  
  def default_subscription_out_of_stock_action
    'skip_month'
  end
  
  def default_subscription_fallback
    'skip_month'
  end
  
  def default_subscription_partial_stock_action
    'accept_partial'
  end
  
  def default_booking_days
    %w[monday tuesday wednesday thursday friday]
  end
  
  def default_booking_times
    %w[09:00 10:00 11:00 14:00 15:00 16:00]
  end
  
  # Platform (BizBlasts) loyalty methods
  def current_platform_loyalty_points
    platform_loyalty_points || 0
  end
  
  def platform_points_earned
    platform_loyalty_transactions.earned.sum(:points_amount)
  end
  
  def platform_points_redeemed
    platform_loyalty_transactions.redeemed.sum(:points_amount).abs
  end
  
  def can_redeem_platform_points?(points_required)
    current_platform_loyalty_points >= points_required
  end
  
  def generate_platform_referral_code
    return platform_referral_code if platform_referral_code.present?
    
    # Generate format: BIZ-BUSINESS_INITIALS-RANDOM
    business_initials = name.split.map(&:first).join.upcase
    random_string = SecureRandom.alphanumeric(6).upcase
    
    code = "BIZ-#{business_initials}-#{random_string}"
    
    # Ensure uniqueness
    while Business.exists?(platform_referral_code: code)
      random_string = SecureRandom.alphanumeric(6).upcase
      code = "BIZ-#{business_initials}-#{random_string}"
    end
    
    update!(platform_referral_code: code)
    code
  end
  
  def add_platform_loyalty_points!(points, description, related_referral = nil)
    platform_loyalty_transactions.create!(
      transaction_type: 'earned',
      points_amount: points,
      description: description,
      related_platform_referral: related_referral
    )
    
    # Update cached points
    increment!(:platform_loyalty_points, points)
  end
  
  def redeem_platform_loyalty_points!(points, description)
    return false unless can_redeem_platform_points?(points)
    
    platform_loyalty_transactions.create!(
      transaction_type: 'redeemed',
      points_amount: -points,
      description: description
    )
    
    # Update cached points
    decrement!(:platform_loyalty_points, points)
    
    true
  end
  
  def platform_loyalty_summary
    {
      current_points: current_platform_loyalty_points,
      total_earned: platform_points_earned,
      total_redeemed: platform_points_redeemed,
      total_referrals_made: platform_referrals_made.count,
      qualified_referrals: platform_referrals_made.qualified.count,
      available_redemptions: PlatformDiscountCode.available_redemptions_for_business(self)
    }
  end
  
  # Define which attributes are allowed to be searched with Ransack
  def self.ransackable_attributes(auth_object = nil)
    %w[id name hostname host_type tier industry time_zone active created_at updated_at stripe_customer_id stripe_status payment_reminders_enabled domain_coverage_applied domain_cost_covered domain_renewal_date]
  end
  
  # Define which associations are allowed to be searched with Ransack
  def self.ransackable_associations(auth_object = nil)
    %w[staff_members services bookings tenant_customers users clients client_businesses subscription integrations]
  end
  
  # Custom ransacker for Stripe status filtering
  ransacker :stripe_status do
    Arel.sql("CASE WHEN stripe_customer_id IS NOT NULL AND stripe_customer_id != '' THEN 'connected' ELSE 'not_connected' END")
  end
  
  # Domain coverage methods for Premium tier
  def eligible_for_domain_coverage?
    premium_tier? && host_type_custom_domain?
  end
  
  def domain_coverage_limit
    20.0 # Fixed at $20/year as per requirements
  end
  
  def domain_coverage_available?
    eligible_for_domain_coverage? && !domain_coverage_applied?
  end
  
  def apply_domain_coverage!(cost, notes = nil, registrar = 'namecheap', auto_renewal = true)
    return false unless eligible_for_domain_coverage?
    return false if cost > domain_coverage_limit
    
    registration_date = Date.current
    coverage_expires = registration_date + 1.year
    next_renewal = registration_date + 1.year
    
    update!(
      domain_coverage_applied: true,
      domain_cost_covered: cost,
      domain_coverage_notes: notes,
      domain_renewal_date: next_renewal,
      domain_coverage_expires_at: coverage_expires,
      domain_registration_date: registration_date,
      domain_registrar: registrar,
      domain_auto_renewal_enabled: auto_renewal
    )
  end
  
  def domain_coverage_status
    return :not_eligible unless eligible_for_domain_coverage?
    return :available if domain_coverage_available?
    return :expired if domain_coverage_applied? && domain_coverage_expired?
    return :applied if domain_coverage_applied?
    :unknown
  end
  
  def domain_coverage_expired?
    domain_coverage_expires_at.present? && domain_coverage_expires_at < Date.current
  end
  
  def domain_coverage_expires_soon?(days = 30)
    domain_coverage_expires_at.present? && 
    domain_coverage_expires_at <= Date.current + days.days
  end
  
  def domain_will_auto_renew?
    domain_auto_renewal_enabled? && domain_renewal_date.present?
  end
  
  def domain_coverage_remaining_days
    return nil unless domain_coverage_expires_at.present?
    return 0 if domain_coverage_expired?
    (domain_coverage_expires_at - Date.current).to_i
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

  
  # Active Storage attachment for business logo with variants
  has_one_attached :logo do |attachable|
    attachable.variant :thumb, resize_to_limit: [120, 120], quality: 80
    attachable.variant :medium, resize_to_limit: [300, 300], quality: 85
    attachable.variant :large, resize_to_limit: [600, 600], quality: 90
  end
  
  # Logo validations
  validates :logo, content_type: { in: %w[image/png image/jpeg image/gif image/webp], 
                                   message: 'must be PNG, JPEG, GIF, or WebP' },
                   size: { less_than: 15.megabytes, message: 'must be less than 15MB' }
  
  # Background processing for logo
  after_commit :process_logo, if: -> { logo.attached? }
  
  def has_visible_products?
    products.active.where(product_type: [:standard, :mixed]).any?(&:visible_to_customers?)
  end

  def has_visible_services?
    services.active.any?
  end
  
  private
  
  def process_logo
    return unless logo.attached?
    
    begin
      return unless logo.blob.byte_size > 2.megabytes
      # Pass the attachment ID instead of the attached object
      ProcessImageJob.perform_later(logo.attachment.id)
    rescue ActiveStorage::FileNotFoundError => e
      Rails.logger.warn "Logo blob not found for business #{id}: #{e.message}"
    rescue => e
      Rails.logger.error "Failed to enqueue logo processing job for business #{id}: #{e.message}"
    end
  end
  
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
  
  def handle_loyalty_program_disabled
    # Only act if loyalty program was disabled (changed from true to false)
    return unless loyalty_program_enabled_before_last_save == true && !loyalty_program_enabled?
    
    # Find all services that use loyalty fallback
    services_with_loyalty_fallback = services.where(
      subscription_enabled: true,
      subscription_rebooking_preference: 'same_day_loyalty_fallback'
    )
    
    if services_with_loyalty_fallback.exists?
      Rails.logger.info "[LOYALTY PROGRAM DISABLED] Converting #{services_with_loyalty_fallback.count} service(s) from loyalty fallback to standard fallback for business #{id}"
      
      # Convert them to the standard fallback option
      services_with_loyalty_fallback.update_all(
        subscription_rebooking_preference: 'same_day_next_month'
      )
    end
  end
end 