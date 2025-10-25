# frozen_string_literal: true

class Business < ApplicationRecord
  # Business represents a tenant in the multi-tenant architecture
  
  # Define the comprehensive list of industries based on showcase examples
  SHOWCASE_INDUSTRY_MAPPINGS = {
    # Services
    hair_salons: "Hair Salons",
    massage_therapy: "Massage Therapy",
    pet_services: "Pet Services",
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
    wellness_services: "Wellness Services",

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
  enum :canonical_preference, { www: 'www', apex: 'apex' }, suffix: true
  enum :status, { 
    active: 'active', 
    inactive: 'inactive', 
    suspended: 'suspended',
    cname_pending: 'cname_pending',
    cname_monitoring: 'cname_monitoring',
    cname_active: 'cname_active',
    cname_timeout: 'cname_timeout'
  }, default: 'active'
  
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
  has_many :locations, dependent: :destroy
  has_one :subscription, dependent: :destroy # Added for Module 7
  has_many :integrations, dependent: :destroy # Added for Module 9
  
  # Tips associations
  has_many :tips, dependent: :destroy
  has_one :tip_configuration, dependent: :destroy

  # SMS associations
  has_many :sms_messages, dependent: :destroy
  has_many :sms_opt_in_invitations, dependent: :destroy
  
  # Calendar integration associations
  has_many :calendar_connections, dependent: :destroy
  
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
  validates :google_place_id, uniqueness: true, allow_nil: true
  validates :tip_mailer_if_no_tip_received, inclusion: { in: [true, false] }
  
  # New Validations for hostname/host_type
  validates :hostname, presence: true, uniqueness: { case_sensitive: false }
  validates :host_type, presence: true, inclusion: { in: host_types.keys }

  # Subdomain format validation – only run if the hostname itself is being modified.
  # This prevents tier/host_type changes from failing validations when the hostname
  # hasn't been altered (e.g. in tests that toggle host_type only).
  validates :hostname,
            format: {
              with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/,
              message: "can only contain lowercase letters, numbers, and single hyphens"
            },
            exclusion: {
              in: %w(www admin mail api help support status blog),
              message: "'%{value}' is reserved."
            },
            if: -> { host_type_subdomain? && (new_record? || will_save_change_to_hostname?) }
            
  # Custom domain format validation – likewise only when hostname is changing.
  validates :hostname,
            format: {
              with: /\A(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9][a-z0-9-]{0,61}[a-z0-9]\z/,
              message: "is not a valid domain name"
            },
            if: -> { host_type_custom_domain? && (new_record? || will_save_change_to_hostname?) }
            
  # Apply subdomain-only rule **only when creating** a Free or Standard business;
  # allows later downgrades from Premium to proceed so DomainRemovalService can run.
  validate :non_premium_requires_subdomain_host_type, if: -> { (free_tier? || standard_tier?) && new_record? }
  
  # Ensure that only Premium tier businesses can have custom domains.
  validate :custom_domain_requires_premium_tier
  
  scope :active, -> { where(active: true) }
  scope :cname_pending, -> { where(status: 'cname_pending') }
  scope :cname_monitoring, -> { where(status: 'cname_monitoring') }
  scope :monitoring_needed, -> { where(cname_monitoring_active: true, status: 'cname_monitoring') }
  
  before_validation :normalize_hostname
  before_validation :ensure_hours_is_hash
  before_validation :normalize_stripe_customer_id
  before_destroy :orphan_all_bookings, prepend: true
  after_save :sync_hours_with_default_location, if: :saved_change_to_hours?
  after_update :handle_loyalty_program_disabled, if: :saved_change_to_loyalty_program_enabled?
  after_update :handle_tier_downgrade, if: :saved_change_to_tier?
  after_update :handle_canonical_preference_change, if: :saved_change_to_canonical_preference?
  after_validation :set_time_zone_from_address, if: :address_components_changed?

  # ---------------------------------------------------------------------------
  # Automatic custom-domain setup triggers
  # ---------------------------------------------------------------------------

  # 1. Newly-registered businesses that signed up for the Premium tier **and**
  #    provided a custom domain should have the CNAME setup sequence started
  #    automatically right after creation.
  after_commit :trigger_custom_domain_setup_after_create, on: :create

  # 2. Send admin notification when a new business registers
  after_commit :send_admin_new_business_notification, on: :create

  # 2. Existing businesses that upgrade to the Premium tier (tier change
  #    detected) and already have a custom-domain host type should also kick
  #    off the setup sequence automatically – but only if the setup hasn't
  #    already been started/completed.
  after_commit :trigger_custom_domain_setup_after_premium_upgrade, on: :update
  after_commit :trigger_custom_domain_setup_after_host_type_change, on: :update

  # 3. Invalidate AllowedHostService cache when custom domain configuration changes
  #    This ensures the host validation cache stays in sync with database changes
  after_save :invalidate_allowed_host_cache, if: :custom_domain_cache_invalidation_needed?

  # Find the current tenant
  def self.current
    ActsAsTenant.current_tenant
  end
  
  # Set the current tenant in ActsAsTenant
  def self.set_current_tenant(business)
    ActsAsTenant.current_tenant = business
  end
  
  def to_param
    id.to_s
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
  
  # Stock management methods
  def stock_management_enabled?
    stock_management_enabled
  end
  
  def stock_management_disabled?
    !stock_management_enabled
  end
  
  # Helper method for products to check if they should track stock
  def requires_stock_tracking?
    stock_management_enabled?
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
    %w[id name hostname host_type tier industry time_zone active created_at updated_at status cname_monitoring_active domain_coverage_applied domain_cost_covered domain_renewal_date stripe_customer_id stripe_status payment_reminders_enabled stock_management_enabled]
  end
  
  # Define which associations are allowed to be searched with Ransack
  def self.ransackable_associations(auth_object = nil)
    %w[staff_members services bookings tenant_customers users clients client_businesses subscription integrations]
  end
  
  # Custom ransacker for Stripe status filtering
  ransacker :stripe_status do
    Arel.sql("CASE WHEN stripe_account_id IS NOT NULL AND stripe_account_id != '' THEN 'connected' ELSE 'not_connected' END")
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

  # CNAME Domain Setup Methods
  def start_cname_monitoring!
    return false unless premium_tier? && host_type_custom_domain?
    
    update!(
      status: 'cname_monitoring',
      cname_monitoring_active: true,
      cname_check_attempts: 0
    )
  end

  def stop_cname_monitoring!
    update!(
      cname_monitoring_active: false,
      status: cname_active? ? 'cname_active' : 'active'
    )
  end

  def cname_due_for_check?
    return false unless cname_monitoring_active?
    return true if cname_check_attempts == 0
    
    # Check every 5 minutes, max 12 attempts (1 hour)
    return false if cname_check_attempts >= 12
    
    last_check = updated_at || Time.current
    Time.current >= last_check + 5.minutes
  end

  def increment_cname_check!
    increment!(:cname_check_attempts)
  end

  def cname_timeout!
    update!(
      status: 'cname_timeout',
      cname_monitoring_active: false
    )
  end

  def cname_success!
    update!(
      status: 'cname_active',
      cname_monitoring_active: false
    )
  end

  # Check if domain health verification is stale and needs rechecking
  def domain_health_stale?(threshold = 1.hour)
    domain_health_checked_at.nil? || domain_health_checked_at < threshold.ago
  end

  def can_setup_custom_domain?
    premium_tier? && host_type_custom_domain? && !cname_active?
  end

  # ---------------------------------------------------------------------------
  # Convenience flag
  # ---------------------------------------------------------------------------
  # Returns true when the business *should* be served from its custom domain –
  # i.e., the tenant *is* a custom-domain host *and* the CNAME/DNS has been
  # validated *and* Render reports the domain attached (SSL issued) *and* 
  # the domain is returning HTTP 200 status.
  def custom_domain_allow?
    premium_tier? && host_type_custom_domain? && cname_active? && render_domain_added? && domain_health_verified?
  end

  # Set domain health status with optimistic locking protection
  # @param verified_status [Boolean] true for verified, false for unverified
  def mark_domain_health_status!(verified_status, retry_count = 0)
    with_lock do
      update!(
        domain_health_verified: verified_status,
        domain_health_checked_at: Time.current
      )
    end
  rescue ActiveRecord::StaleObjectError => e
    Rails.logger.warn "[Business] Optimistic lock conflict when marking domain health #{verified_status ? 'verified' : 'unverified'} for business #{id}: #{e.message}"
    
    if retry_count < 1
      # Reload and retry once
      reload
      mark_domain_health_status!(verified_status, retry_count + 1)
    else
      raise e
    end
  end

  # Method to get the full URL for this business
  def full_url(path = nil)
    # Determine host based on environment and host_type
    host = if Rails.env.development?
      # Development: use lvh.me with subdomain
      "#{(subdomain.presence || hostname)}.lvh.me"
    elsif host_type_custom_domain?
      # Custom domain: use full hostname
      hostname
    else
      # Subdomain in other envs: append main domain
      "#{(subdomain.presence || hostname)}.bizblasts.com"
    end

    # Determine protocol
    protocol = Rails.env.development? ? 'http://' : 'https://'

    # Determine port in development from action_mailer default_url_options
    port = ''
    if Rails.env.development?
      default_opts = Rails.application.config.action_mailer.default_url_options rescue {}
      port = ":#{default_opts[:port]}" if default_opts[:port].present?
    end

    # Construct full URL
    full_url = "#{protocol}#{host}#{port}"
    full_url += "/#{path.to_s.gsub(/^\//, '')}" if path.present?
    full_url
  end

  def has_visible_products?
    products.active.where(product_type: [:standard, :mixed]).any?(&:visible_to_customers?)
  end

  def has_visible_services?
    services.active.any?
  end
  
  # ---------------- Time zone helpers ----------------
  def full_address
    [address, city, state, zip].compact.join(', ')
  end

  def address_components_changed?
    saved_change_to_address? || saved_change_to_city? || saved_change_to_state? || saved_change_to_zip?
  end

  def set_time_zone_from_address
    begin
      result = Geocoder.search(full_address).first
      tz = result&.data&.dig('timezone') || result&.timezone

      if tz.blank? && state.present?
        # Simple US state fallback mapping
        state_map = {
          'AL' => 'America/Chicago', 'AK' => 'America/Anchorage', 'AZ' => 'America/Phoenix',
          'AR' => 'America/Chicago', 'CA' => 'America/Los_Angeles', 'CO' => 'America/Denver',
          'CT' => 'America/New_York', 'DE' => 'America/New_York', 'FL' => 'America/New_York',
          'GA' => 'America/New_York', 'HI' => 'Pacific/Honolulu', 'ID' => 'America/Boise',
          'IL' => 'America/Chicago', 'IN' => 'America/Indiana/Indianapolis', 'IA' => 'America/Chicago',
          'KS' => 'America/Chicago', 'KY' => 'America/New_York', 'LA' => 'America/Chicago',
          'ME' => 'America/New_York', 'MD' => 'America/New_York', 'MA' => 'America/New_York',
          'MI' => 'America/Detroit', 'MN' => 'America/Chicago', 'MS' => 'America/Chicago',
          'MO' => 'America/Chicago', 'MT' => 'America/Denver', 'NE' => 'America/Chicago',
          'NV' => 'America/Los_Angeles', 'NH' => 'America/New_York', 'NJ' => 'America/New_York',
          'NM' => 'America/Denver', 'NY' => 'America/New_York', 'NC' => 'America/New_York',
          'ND' => 'America/Chicago', 'OH' => 'America/New_York', 'OK' => 'America/Chicago',
          'OR' => 'America/Los_Angeles', 'PA' => 'America/New_York', 'RI' => 'America/New_York',
          'SC' => 'America/New_York', 'SD' => 'America/Chicago', 'TN' => 'America/Chicago',
          'TX' => 'America/Chicago', 'UT' => 'America/Denver', 'VT' => 'America/New_York',
          'VA' => 'America/New_York', 'WA' => 'America/Los_Angeles', 'WV' => 'America/New_York',
          'WI' => 'America/Chicago', 'WY' => 'America/Denver'
        }

        # Accept full state names too
        full_state_map = {
          'Alabama' => 'AL', 'Alaska' => 'AK', 'Arizona' => 'AZ', 'Arkansas' => 'AR',
          'California' => 'CA', 'Colorado' => 'CO', 'Connecticut' => 'CT', 'Delaware' => 'DE',
          'Florida' => 'FL', 'Georgia' => 'GA', 'Hawaii' => 'HI', 'Idaho' => 'ID',
          'Illinois' => 'IL', 'Indiana' => 'IN', 'Iowa' => 'IA', 'Kansas' => 'KS',
          'Kentucky' => 'KY', 'Louisiana' => 'LA', 'Maine' => 'ME', 'Maryland' => 'MD',
          'Massachusetts' => 'MA', 'Michigan' => 'MI', 'Minnesota' => 'MN', 'Mississippi' => 'MS',
          'Missouri' => 'MO', 'Montana' => 'MT', 'Nebraska' => 'NE', 'Nevada' => 'NV',
          'New Hampshire' => 'NH', 'New Jersey' => 'NJ', 'New Mexico' => 'NM', 'New York' => 'NY',
          'North Carolina' => 'NC', 'North Dakota' => 'ND', 'Ohio' => 'OH', 'Oklahoma' => 'OK',
          'Oregon' => 'OR', 'Pennsylvania' => 'PA', 'Rhode Island' => 'RI', 'South Carolina' => 'SC',
          'South Dakota' => 'SD', 'Tennessee' => 'TN', 'Texas' => 'TX', 'Utah' => 'UT',
          'Vermont' => 'VT', 'Virginia' => 'VA', 'Washington' => 'WA', 'West Virginia' => 'WV',
          'Wisconsin' => 'WI', 'Wyoming' => 'WY'
        }

        abbr = state_map.key?(state) ? state : full_state_map[state]
        tz = state_map[abbr] if abbr
      end

      self.time_zone = tz if tz.present?
    rescue => e
      SecureLogger.warn "[Business] Failed to look up timezone for address: #{e.message}"
    end
  end
  
  # Ensure time_zone present by performing lookup if blank
  def ensure_time_zone!
    return time_zone if time_zone.present? && time_zone != 'UTC'

    set_time_zone_from_address if respond_to?(:set_time_zone_from_address)
    save(validate: false) if time_zone_changed? && persisted?
    time_zone
  end

  # Active Storage attachment for business logo with variants
  has_one_attached :logo do |attachable|
    attachable.variant :thumb, resize_to_limit: [120, 120], quality: 80
    attachable.variant :medium, resize_to_limit: [300, 300], quality: 85
    attachable.variant :large, resize_to_limit: [600, 600], quality: 90
  end
  
  # Logo validations - Updated for HEIC support
  validates :logo, **FileUploadSecurity.image_validation_options
  
  # Background processing for logo
  after_commit :process_logo, if: -> { logo.attached? }

  # Ensure hostname is populated for subdomain host_type
  before_validation :sync_hostname_with_subdomain, if: :host_type_subdomain?

  # Get the canonical domain based on the business's canonical preference
  # This is the domain that should be used for links, health checks, etc.
  def canonical_domain
    return nil unless hostname.present? && host_type_custom_domain?
    
    apex_domain = hostname.sub(/^www\./, '')
    
    case canonical_preference
    when 'www'
      "www.#{apex_domain}"
    when 'apex'
      apex_domain
    else
      # Fallback to stored hostname if preference is unknown
      hostname
    end
  end

  # SMS-related methods
  def sms_enabled_for?(type)
    return false unless sms_enabled?
    
    case type.to_sym
    when :marketing
      sms_enabled? && sms_marketing_enabled?
    when :transactional, :booking, :order, :payment, :reminder, :system, :subscription
      sms_enabled?
    else
      sms_enabled?
    end
  end

  def can_send_sms?
    sms_enabled? && Rails.application.config.sms_enabled && !free_tier?
  end

  def sms_auto_invitations_enabled?
    # Check if auto-invitations are enabled for this business
    # Defaults to true if column doesn't exist yet (migration pending)
    respond_to?(:sms_auto_invitations_enabled) ? sms_auto_invitations_enabled : true
  end

  def free_tier?
    tier == 'free'
  end

  def sms_daily_limit
    # SMS limits based on tier
    case tier
    when 'premium'
      1000
    when 'standard'
      500
    when 'free'
      0  # Free tier cannot send SMS
    else
      0  # Default to no SMS for unknown tiers
    end
  end

  # Helper method to get a safe business identifier for logging
  # Returns the business ID if persisted, otherwise returns a descriptive string
  # This prevents confusing log messages when business objects are not yet saved to the database
  def safe_identifier_for_logging
    if persisted?
      id
    else
      "unpersisted_business_#{name || 'unknown'}_#{object_id}"
    end
  end
  
  # ---------------------------------------------------------------------------
  # Private callback helper methods
  # ---------------------------------------------------------------------------
  private

  # Returns the most reliable host for critical mailer URLs (payments, invoices)
  # Always defaults to subdomain for maximum reliability unless explicitly overridden
  def mailer_host(prefer_custom_domain: false)
    # For critical links (payments/invoices), default to reliable subdomain
    # Only use custom domain if explicitly requested AND fully verified
    if prefer_custom_domain && custom_domain_fully_functional?
      hostname
    else
      # Always fall back to reliable subdomain for critical links
      "#{subdomain}.bizblasts.com"
    end
  end

  # Checks if custom domain is not just allowed, but actually functional
  def custom_domain_fully_functional?
    custom_domain_allow? && 
    status == 'cname_active' && 
    render_domain_added? &&
    domain_health_verified? &&
    hostname.present? &&
    # Additional safety: ensure hostname doesn't contain any suspicious patterns
    hostname.match?(/\A[a-zA-Z0-9.-]+\z/)
  end

  # Triggered after *create* for eligible businesses.
  def trigger_custom_domain_setup_after_create
    return unless premium_tier? && host_type_custom_domain? && hostname.present?
    return if Rails.env.test? # avoid interfering with specs

    # Run domain setup in background to prevent 502 crashes from external API calls
    Rails.logger.info "[BUSINESS CALLBACK] Queueing custom-domain setup for newly created Business ##{id} (#{hostname})"
    CustomDomainSetupJob.perform_later(id)
  end

  # Triggered after *create* to send admin notification about new business registration
  def send_admin_new_business_notification
    return if Rails.env.test? # avoid interfering with specs
    return unless ENV['ADMIN_EMAIL'].present?

    # Find the business owner (manager role user)
    owner = users.find_by(role: 'manager')
    return unless owner.present?

    begin
      Rails.logger.info "[BUSINESS CALLBACK] Sending admin notification for new business registration: #{name} (ID: #{id})"
      AdminMailer.new_business_registration(self, owner).deliver_later(queue: 'mailers')
    rescue => e
      Rails.logger.error "[BUSINESS CALLBACK] Failed to send admin notification for business #{id}: #{e.message}"
    end
  end

  # Triggered after *update* when a non-premium business upgrades to Premium.
  def trigger_custom_domain_setup_after_premium_upgrade
    return if Rails.env.test?
    return unless saved_change_to_tier? && tier == 'premium'

    # Only act when moving *to* premium, not any other tier change.
    old_tier, new_tier = saved_change_to_tier
    return unless old_tier != 'premium' && new_tier == 'premium'

    return unless host_type_custom_domain? && hostname.present?

    # Skip if setup already in progress or completed.
    return if cname_pending? || cname_monitoring? || cname_active?

    # Run domain setup in background to prevent 502 crashes from external API calls
    Rails.logger.info "[BUSINESS CALLBACK] Queueing custom-domain setup for Business ##{id} after tier upgrade (#{old_tier} -> premium)"
    CustomDomainSetupJob.perform_later(id)
  end

  # Triggered after *update* when host_type changes from subdomain -> custom_domain on a premium business.
  def trigger_custom_domain_setup_after_host_type_change
    return if Rails.env.test?
    return unless saved_change_to_host_type? && host_type_custom_domain?
    return unless premium_tier? && hostname.present?
    # Skip if setup already running or completed
    return if cname_pending? || cname_monitoring? || cname_active?
    
    # Run domain setup in background to prevent 502 crashes from external API calls
    Rails.logger.info "[BUSINESS CALLBACK] Queueing custom-domain setup for Business ##{id} after host_type change (subdomain -> custom_domain)"
    CustomDomainSetupJob.perform_later(id)
  end

  # Determines if we need to invalidate the AllowedHostService cache
  # Cache invalidation is needed when:
  # - hostname changes (domain name changed)
  # - status changes (domain activation state changed)
  # - host_type changes (switching between subdomain/custom_domain)
  # AND the business uses (or USED to use) custom domains
  def custom_domain_cache_invalidation_needed?
    # Check if business is currently OR was previously using custom domains
    # This handles the case where host_type changes from custom_domain to subdomain
    is_or_was_custom_domain = host_type_custom_domain? ||
                               (saved_change_to_host_type? && saved_change_to_host_type[0] == 'custom_domain')

    is_or_was_custom_domain &&
      (saved_change_to_hostname? || saved_change_to_status? || saved_change_to_host_type?)
  end

  # Invalidates the AllowedHostService cache for this business's custom domain
  # This ensures that host validation reflects the latest database state
  #
  # Uses exact key deletion instead of pattern matching for better performance
  # and compatibility with all cache stores (e.g., Memcached doesn't support patterns)
  def invalidate_allowed_host_cache
    hostnames_to_invalidate = []

    # If hostname changed, invalidate BOTH old and new values
    if saved_change_to_hostname?
      old_hostname, new_hostname = saved_change_to_hostname
      hostnames_to_invalidate << old_hostname if old_hostname.present?
      hostnames_to_invalidate << new_hostname if new_hostname.present?
    else
      # No hostname change - just invalidate current hostname
      hostnames_to_invalidate << hostname if hostname.present?
    end

    # Invalidate cache for each hostname (old and/or new)
    hostnames_to_invalidate.each do |host|
      # Generate candidates the SAME way as AllowedHostService.valid_custom_domain?
      # This ensures we construct the exact same cache key
      root = host.downcase.sub(/\Awww\./, '')
      candidates = [host.downcase, root, "www.#{root}"].uniq.map(&:downcase)

      # Sort candidates the same way as the service does when creating the key
      sorted_candidates = candidates.sort

      # Construct the exact cache key used by AllowedHostService
      cache_key = "allowed_host:custom_domain:#{sorted_candidates.join(':')}"

      # Delete the exact key (works with all cache stores, more efficient than pattern matching)
      Rails.cache.delete(cache_key)
    end

    Rails.logger.info "[AllowedHostService] Cache invalidated for custom domain changes"
  end

  # ---------------------------------------------------------------------------
  # Existing private methods continue below
  # ---------------------------------------------------------------------------
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
    self.hostname = hostname.to_s.downcase.strip
    # No longer perform aggressive gsub cleaning for subdomains here,
    # let the format validator handle invalid characters/structures.
  end
  # Keeps hostname in sync with subdomain for subdomain-based tenants.
  # • Never overwrites an explicitly provided hostname on create.
  # • If the subdomain changes later and hostname wasn't modified in the
  #   same operation, bring hostname back in sync.
  # • Also fill hostname when it's blank.
  def sync_hostname_with_subdomain
    return unless host_type_subdomain?
    return if subdomain.blank?

    if hostname.blank?
      self.hostname = subdomain.to_s.downcase.strip
    elsif will_save_change_to_subdomain? && !will_save_change_to_hostname?
      self.hostname = subdomain.to_s.downcase.strip
    end
  end

  def normalize_stripe_customer_id
    # Convert empty strings to nil to avoid unique constraint violations
    # since multiple nil values are allowed but multiple empty strings are not
    self.stripe_customer_id = nil if stripe_customer_id.blank?
  end
  
  # Validation helper: Free **and Standard** tiers can only use BizBlasts sub-domains.
  # Runs only when creating or updating a non-premium business.
  def non_premium_requires_subdomain_host_type
    return if host_type_subdomain?
    errors.add(:host_type, "must be 'subdomain' for Free and Standard tiers")
  end

  # Keep old method name as alias for backwards compatibility (e.g., specs).
  alias_method :free_tier_requires_subdomain_host_type, :non_premium_requires_subdomain_host_type
  
  # Validation helper: prevent non-premium businesses from using custom domains.
  def custom_domain_requires_premium_tier
    return unless host_type_custom_domain?
 
    # --- Allow downgrades ----------------------------------------------------
    # If the business is *downgrading* from premium, let the record save so that
    # the `handle_tier_downgrade` callback can subsequently remove the custom
    # domain.  A downgrade is detected when the tier is changing **from**
    # 'premium' **to** a different value.
    if will_save_change_to_tier? && tier_was == 'premium' && tier != 'premium'
      return # skip validation – downgrade will be handled after save
    end

    # For all other cases (creates, upgrades, edits) enforce the rule.
    final_tier = if will_save_change_to_tier? && tier.present?
                   tier                           # new value about to be saved
                 else
                   tier_was || tier              # previous persisted value (or current)
                 end

    unless final_tier == 'premium'
      errors.add(:tier, 'must be premium to use a custom domain')
    end
  end
  
  # Returns true if the tier *before the current change* was premium.  Works
  # in validations (before save) because `tier_was` contains the previously
  # persisted value.
  def premium_tier_was?
    tier_was == 'premium'
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

  def handle_tier_downgrade
    # Only act if tier changed and business has custom domain
    return unless saved_change_to_tier? && host_type_custom_domain?
    
    old_tier, new_tier = saved_change_to_tier
    
    # Remove custom domain if downgrading from premium
    if old_tier == 'premium' && new_tier != 'premium'
      Rails.logger.info "[TIER DOWNGRADE] Removing custom domain due to tier change from #{old_tier} to #{new_tier} for business #{id}"
      
      begin
        removal_service = DomainRemovalService.new(self)
        result = removal_service.handle_tier_downgrade!(new_tier)
        
        Rails.logger.info "[TIER DOWNGRADE] Domain removal result: #{result[:success] ? 'success' : 'failed'}"
      rescue => e
        Rails.logger.error "[TIER DOWNGRADE] Failed to remove domain: #{e.message}"
      end
    end
  end

  def handle_canonical_preference_change
    # Only act if business has active custom domain
    return unless host_type_custom_domain? && cname_active? && render_domain_added?
    
    old_preference, new_preference = saved_change_to_canonical_preference
    
    Rails.logger.info "[CANONICAL PREFERENCE CHANGE] Updating Render domains from #{old_preference} to #{new_preference} for business #{id}"
    
    begin
      # Remove and re-add domain with new canonical preference
      setup_service = CnameSetupService.new(self)
      
      # First remove existing domains
      render_service = RenderDomainService.new
      apex_domain = hostname.sub(/^www\./, '')
      
      [apex_domain, "www.#{apex_domain}"].each do |domain_name|
        domain = render_service.find_domain_by_name(domain_name)
        if domain
          Rails.logger.info "[CANONICAL PREFERENCE CHANGE] Removing domain: #{domain_name}"
          render_service.remove_domain(domain['id'])
        end
      end
      
      # Re-add with new canonical preference
      setup_service.send(:add_domain_to_render!)
      # Auto-trigger verification of both variants in Render
      setup_service.send(:verify_render_domains!)
      
      Rails.logger.info "[CANONICAL PREFERENCE CHANGE] Successfully updated canonical preference"
      
    rescue => e
      Rails.logger.error "[CANONICAL PREFERENCE CHANGE] Failed to update domains: #{e.message}"
      # Don't raise - this is a background operation
    end
  end
end 