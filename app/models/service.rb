# frozen_string_literal: true

class Service < ApplicationRecord
  include TenantScoped
  
  acts_as_tenant(:business)
  belongs_to :business
  has_many :staff_assignments, dependent: :destroy
  has_many :assigned_staff, through: :staff_assignments, source: :user
  has_many :services_staff_members, dependent: :destroy
  has_many :staff_members, through: :services_staff_members
  has_many :bookings
  
  # Add-on products association
  has_many :product_service_add_ons, dependent: :destroy
  has_many :add_on_products, through: :product_service_add_ons, source: :product
  
  # Promotion associations
  has_many :promotion_services, dependent: :destroy
  has_many :promotions, through: :promotion_services
  
  # Subscription associations
  has_many :customer_subscriptions, dependent: :destroy
  
  # Image attachments
  has_many_attached :images do |attachable|
    attachable.variant :thumb, resize_to_limit: [300, 300]
    attachable.variant :medium, resize_to_limit: [800, 800] 
    attachable.variant :large, resize_to_limit: [1200, 1200]
  end

  # Ensure `images.ordered` is available on the ActiveStorage proxy
  def images
    proxy = super
    proxy.define_singleton_method(:ordered) do
      proxy.attachments.order(:position)
    end
    proxy
  end

  # Define service types
  enum :service_type, { standard: 0, experience: 1 }
  
  # Callbacks
  # before_destroy :orphan_bookings  # Removed - Business model handles orphaning
  
  # Process images after commit for optimization
  after_commit :process_images, on: [:create, :update]
  
  validates :name, presence: true
  validates :name, uniqueness: { scope: :business_id }
  validates :duration, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :active, inclusion: { in: [true, false] }
  validates :business_id, presence: true
  validates :tips_enabled, inclusion: { in: [true, false] }
  validates :subscription_enabled, inclusion: { in: [true, false] }
  validates :subscription_discount_percentage, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_blank: true
  validates :allow_customer_preferences, inclusion: { in: [true, false] }
  validates :allow_discounts, inclusion: { in: [true, false] }
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Validations for images - Updated for 15MB max
  validates :images, content_type: { in: ['image/png', 'image/jpeg', 'image/gif', 'image/webp'], 
                                     message: 'must be a valid image format (PNG, JPEG, GIF, WebP)' }, 
                     size: { less_than: 15.megabytes, message: 'must be less than 15MB' }
  
  validate :image_size_validation
  validate :image_format_validation
  validate :loyalty_program_required_for_loyalty_fallback
  
  # Validations for min/max bookings and spots based on type
  validates :min_bookings, numericality: { only_integer: true, greater_than_or_equal_to: 1 }, if: :experience?
  validates :max_bookings, numericality: { only_integer: true, greater_than_or_equal_to: :min_bookings }, if: :experience?
  validates :spots, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, if: :experience?
  validates :min_bookings, absence: true, if: :standard? # Ensure these are not set for standard
  validates :max_bookings, absence: true, if: :standard? # Ensure these are not set for standard
  validates :spots, absence: true, if: :standard? # Ensure these are not set for standard
  
  # Initialize spots for experience services before validation on create
  before_validation :set_initial_spots, if: :experience?, on: :create
  
  scope :active, -> { where(active: true) }
  scope :featured, -> { where(featured: true) }
  
  # Position management
  scope :positioned, -> { order(:position, :created_at) }
  scope :by_position, -> { order(:position) }
  
  # Set position before creation if not set
  before_create :set_position_to_end, unless: :position?
  after_destroy :resequence_positions
  
  # Optional: Define an enum for duration if you have standard lengths
  # enum duration_minutes: { thirty_minutes: 30, sixty_minutes: 60, ninety_minutes: 90 }
  
  # Define ransackable attributes for ActiveAdmin
  def self.ransackable_attributes(auth_object = nil)
    %w[id name description duration price active business_id created_at updated_at featured service_type min_bookings max_bookings spots allow_discounts]
  end
  
  # Define ransackable associations for ActiveAdmin
  def self.ransackable_associations(auth_object = nil)
    %w[business bookings staff_assignments assigned_staff services_staff_members staff_members product_service_add_ons add_on_products images_attachments images_blobs]
  end

  def available_add_on_products
    # Only include service and mixed products as add-ons
    add_on_products.active.where(product_type: [:service, :mixed])
                       .includes(:product_variants) # Eager load variants for the form
                       .where.not(product_variants: { id: nil }) # Ensure they have variants
  end
  
  # Promotional pricing methods
  def current_promotion
    Promotion.active_promotion_for_service(self)
  end
  
  def on_promotion?
    current_promotion.present?
  end
  
  def promotional_price
    return price unless on_promotion?
    current_promotion.calculate_promotional_price(price)
  end
  
  def promotion_discount_amount
    return 0 unless on_promotion?
    current_promotion.calculate_discount(price)
  end
  
  def promotion_display_text
    return nil unless on_promotion?
    current_promotion.display_text
  end
  
  def savings_percentage
    return 0 unless on_promotion? && price > 0
    ((promotion_discount_amount / price) * 100).round
  end
  
  # Tip eligibility methods
  def tip_eligible?
    tips_enabled?
  end
  
  # Discount eligibility methods
  def discount_eligible?
    allow_discounts?
  end
  
  def tip_timing
    case service_type
    when 'standard'
      :after_service  # Tips on invoice payment
    when 'experience'
      :after_experience  # Special handling - pay now, tip later
    else
      :immediate  # Default behavior
    end
  end

  # Subscription methods
  def subscription_price
    return price unless subscription_enabled?
    price - subscription_discount_amount
  end
  
  def subscription_discount_amount
    return 0 unless subscription_enabled? || business&.subscription_discount_percentage.blank?
    (price * (business.subscription_discount_percentage / 100.0)).round(2)
  end
  
  def subscription_savings_percentage
    return 0 if price.zero? || !subscription_enabled?
    ((subscription_discount_amount / price) * 100).round
  end
  
  def can_be_subscribed?
    active? && subscription_enabled?
  end
  
  def subscription_display_price
    subscription_enabled? ? subscription_price : price
  end
  
  def subscription_display_savings
    return nil unless subscription_enabled? && business&.subscription_discount_percentage.present?
    "Save #{subscription_savings_percentage}% with recurring bookings"
  end
  
  def allow_customer_preferences?
    # Allow customers to set preferences for subscription services
    subscription_enabled?
  end
  
  def allow_any_staff?
    # Allow any staff member to perform this service if needed
    # This could be made configurable per service
    true
  end
  
  def duration_minutes(variant = nil)
    base_duration(variant)
  end

  # Position management methods
  def move_to_position(new_position)
    return if position == new_position
    
    transaction do
      if new_position > position
        # Moving down: shift items up
        business.services.where(position: (position + 1)..new_position).update_all('position = position - 1')
      else
        # Moving up: shift items down
        business.services.where(position: new_position...position).update_all('position = position + 1')
      end
      
      update!(position: new_position)
    end
  end
  
  def move_to_top
    move_to_position(0)
  end
  
  def move_to_bottom
    move_to_position(business.services.maximum(:position) || 0)
  end

  # Custom setter to handle nested image attributes (primary flags & ordering)
  # This logic is adapted from the Product model and assumes similar ActiveAdmin handling
  def images_attributes=(attrs)
    return if attrs.blank?
    
    # Normalize to array of attribute hashes
    attrs_list = attrs.is_a?(Hash) ? attrs.values : Array(attrs)
    return if attrs_list.empty?

    # Process deletions first
    attrs_list.each do |image_attrs|
      next unless image_attrs[:id].present? && ActiveModel::Type::Boolean.new.cast(image_attrs[:_destroy])
      
      attachment = images.attachments.find_by(id: image_attrs[:id])
      if attachment
        attachment.purge_later # Use purge_later for better performance
      else
        Rails.logger.warn("Attempted to delete non-existent image attachment: #{image_attrs[:id]}")
      end
    end

    # Process remaining updates (primary flags and positions)
    remaining_attrs = attrs_list.reject { |attrs| ActiveModel::Type::Boolean.new.cast(attrs[:_destroy]) }
    
    remaining_attrs.each do |image_attrs|
      next unless image_attrs[:id].present?
      
      attachment = images.attachments.find_by(id: image_attrs[:id])
      unless attachment
        errors.add(:images, "Image with ID #{image_attrs[:id]} not found")
        next
      end

      # Update primary flag
      if image_attrs.key?(:primary)
        is_primary = ActiveModel::Type::Boolean.new.cast(image_attrs[:primary])
        if is_primary
          # Unset all other primary flags first
          images.attachments.where.not(id: attachment.id).update_all(primary: false)
          attachment.update(primary: true)
        else
          attachment.update(primary: false)
        end
      end

      # Update position
      if image_attrs.key?(:position)
        attachment.update(position: image_attrs[:position].to_i)
      end
    end
  end

  def primary_image
    # Return the primary image if marked, otherwise nil
    images.attachments.order(:position).find_by(primary: true)
  end

  has_many :service_variants, dependent: :destroy
  accepts_nested_attributes_for :service_variants, allow_destroy: true

  # Return primary (first) variant for convenience
  def default_variant
    @default_variant ||= service_variants.by_position.first
  end

  # Convenience wrappers to favour variant price/duration when available
  def base_price(variant = nil)
    (variant || default_variant)&.price || price
  end

  def base_duration(variant = nil)
    (variant || default_variant)&.duration || duration
  end

  private

  def image_size_validation
    images.each do |image|
      if image.blob.byte_size > 15.megabytes
        errors.add(:images, "must be less than 15MB")
      end
    end
  end
  
  def image_format_validation
    images.each do |image|
      unless image.blob.content_type.in?(['image/jpeg', 'image/png', 'image/gif', 'image/webp'])
        errors.add(:images, "must be a valid image format (JPEG, PNG, GIF, WebP)")
      end
    end
  end

  def process_images
    images.each do |image|
      # Create optimized variants after upload in background
      ProcessImageJob.perform_later(image.id)
    end
  end

  def set_initial_spots
    # For 'Experience' services, initialize spots with max_bookings if not already set
    self.spots = max_bookings if spots.nil? && max_bookings.present?
  end
  
  def loyalty_program_required_for_loyalty_fallback
    return unless subscription_enabled? && subscription_rebooking_preference == 'same_day_loyalty_fallback'
    
    unless business&.loyalty_program_active?
      errors.add(:subscription_rebooking_preference, 
        'cannot use loyalty points fallback when loyalty program is not enabled. Please enable your loyalty program first or choose a different rebooking option.')
    end
  end
  
  # Safe method to get rebooking preference - falls back if loyalty program is disabled
  def effective_subscription_rebooking_preference
    return subscription_rebooking_preference unless subscription_rebooking_preference == 'same_day_loyalty_fallback'
    
    # If loyalty fallback is set but loyalty program is disabled, use standard fallback
    if business&.loyalty_program_active?
      'same_day_loyalty_fallback'
    else
      Rails.logger.warn "[SERVICE #{id}] Loyalty fallback requested but loyalty program disabled. Using standard fallback instead."
      'same_day_next_month'
    end
  end

  def set_position_to_end
    max_position = business&.services&.maximum(:position) || -1
    self.position = max_position + 1
  end
  
  def resequence_positions
    business.services.where('position > ?', position).update_all('position = position - 1')
  end
  
  # Class method to resequence all positions for a business
  def self.resequence_for_business(business)
    business.services.positioned.each_with_index do |service, index|
      service.update_column(:position, index) if service.position != index
    end
  end
end 