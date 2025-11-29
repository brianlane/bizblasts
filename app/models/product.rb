# app/models/product.rb
class Product < ApplicationRecord
  # Assuming TenantScoped concern handles belongs_to :business and default scoping
  include TenantScoped
  include DurationFormatting

  has_many :product_variants, -> { order(:id) }, dependent: :destroy
  # If variants are mandatory, line_items might associate through variants
  # has_many :line_items, dependent: :destroy # Use this if products DON'T have variants
  has_many :line_items, through: :product_variants # Use this if products MUST have variants

  has_many_attached :images do |attachable|
    # Quality handled by ProcessImageJob
    attachable.variant :thumb, resize_to_fill: [400, 300]
    attachable.variant :medium, resize_to_fill: [1200, 900] 
    attachable.variant :large, resize_to_limit: [2000, 2000]
  end

  # Ensure `images.ordered` is available on the ActiveStorage proxy
  def images
    proxy = super
    proxy.define_singleton_method(:ordered) do
      proxy.attachments.order(:position)
    end
    proxy
  end

  # Add-ons association
  has_many :product_service_add_ons, dependent: :destroy
  has_many :add_on_services, through: :product_service_add_ons, source: :service
  
  # Promotion associations
  has_many :promotion_products, dependent: :destroy
  has_many :promotions, through: :promotion_products
  
  # Subscription associations
  has_many :customer_subscriptions, dependent: :destroy

  enum :product_type, { standard: 0, service: 1, mixed: 2, rental: 3 }
  
  # Rental category types
  RENTAL_CATEGORIES = %w[equipment vehicle space property tool electronics furniture sports other].freeze
  
  # Location association (for rentals)
  belongs_to :location, optional: true
  
  # Rental bookings association
  has_many :rental_bookings, dependent: :restrict_with_error

  include PriceDurationParser

  validates :name, presence: true, uniqueness: { scope: :business_id }
  validates :product_type, presence: true
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }                                                                              
  
  # Use shared parsing logic
  price_parser :price
  validates :tips_enabled, inclusion: { in: [true, false] }
  validates :subscription_enabled, inclusion: { in: [true, false] }
  validates :subscription_discount_percentage, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_blank: true
  validates :allow_customer_preferences, inclusion: { in: [true, false] }
  validates :allow_discounts, inclusion: { in: [true, false] }
  validates :show_stock_to_customers, inclusion: { in: [true, false] }
  validates :hide_when_out_of_stock, inclusion: { in: [true, false] }
  validates :variant_label_text, length: { maximum: 100 }
  
  # Rental-specific validations
  validates :hourly_rate, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :weekly_rate, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :security_deposit, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :rental_quantity_available, numericality: { only_integer: true, greater_than: 0 }, if: :rental?
  validates :min_rental_duration_mins, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :max_rental_duration_mins, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :rental_buffer_mins, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :rental_category, inclusion: { in: RENTAL_CATEGORIES }, if: :rental?
  validate :min_rental_not_greater_than_max
  validate :rental_must_have_daily_rate, if: :rental?
  validate :rental_duration_options_valid, if: :rental?
  validate :rental_schedule_structure, if: :rental?
  
  # Validate attachments using built-in ActiveStorage validators - Updated for 15MB max with HEIC support
  validates :images, **FileUploadSecurity.image_validation_options
  
  validate :image_size_validation
  validate :validate_pending_image_attributes
  validate :image_format_validation
  validate :price_format_valid

  # TODO: Add method or validation for primary image designation if needed
  # TODO: Add method for image ordering if needed

  scope :active, -> { where(active: true) }
  scope :featured, -> { where(featured: true) }
  scope :rentals, -> { where(product_type: :rental) }
  scope :non_rentals, -> { where.not(product_type: :rental) }
  scope :by_rental_category, ->(category) { rentals.where(rental_category: category) }

  # Allows creating variants directly when creating/updating a product
  accepts_nested_attributes_for :product_variants, allow_destroy: true
  
  # Allow nested attributes for image attachments (for deletion, primary, positioning)
  # Note: This is handled by the custom images_attributes= setter method above

  # Ensure products without explicit variants have a default variant for cart operations
  after_create :create_default_variant
  
  # Process images after commit for optimization
  after_commit :process_images, on: [:create, :update]

  # --- Add Ransack methods --- 
  def self.ransackable_attributes(auth_object = nil)
    # Allowlist attributes for searching/filtering in ActiveAdmin
    # Include basic fields, foreign keys, flags, timestamps, and rental fields
    %w[id name description price active featured business_id created_at updated_at product_type 
       allow_discounts show_stock_to_customers hide_when_out_of_stock variant_label_text
       hourly_rate weekly_rate security_deposit rental_quantity_available rental_category
       min_rental_duration_mins max_rental_duration_mins rental_buffer_mins
       allow_hourly_rental allow_daily_rental allow_weekly_rental location_id]
  end

  def self.ransackable_associations(auth_object = nil)
    # Allowlist associations for searching/filtering in ActiveAdmin
    %w[business product_variants line_items images_attachments images_blobs product_service_add_ons add_on_services location rental_bookings]
  end
  # --- End Ransack methods ---

  # Delegate stock check to variants if they exist, otherwise check product stock
  def in_stock?(requested_quantity = 1)
    return true if business&.stock_management_disabled?
    
    if product_variants.any?
      product_variants.sum(:stock_quantity) >= requested_quantity
    else
      stock_quantity >= requested_quantity
    end
  end

  # If products can be sold without variants, add stock field and validation
  validates :stock_quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, unless: -> { has_variants? || business&.stock_management_disabled? }
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  after_initialize :set_default_product_type, if: :new_record?

  def has_variants?
    product_variants.exists?  
  end

  # Check if product should be visible to customers
  def visible_to_customers?
    return false unless active? # Inactive products are never visible
    
    # Skip stock-based visibility if stock management is disabled
    if hide_when_out_of_stock? && business&.requires_stock_tracking?
      return false unless in_stock?(1)
    end
    
    true
  end

  def primary_image
    images.find_by(primary: true)
  end

  def set_primary_image(image)
    images.update_all(primary: false)
    image.update(primary: true)
  end

  def set_default_product_type
    self.product_type ||= :standard
  end

  def reorder_images(order)
    order.each_with_index do |id, index|
      images.find(id).update(position: index)
    end
  end

  # Promotional pricing methods
  def current_promotion
    Promotion.active_promotion_for_product(self)
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

  # Subscription methods
  def subscription_price
    return price unless subscription_enabled?
    price - subscription_discount_amount
  end
  
  def subscription_discount_amount
    # Apply discount only when subscriptions are enabled and a discount percentage is configured.
    return 0 unless subscription_enabled?

    discount_pct = subscription_discount_percentage.presence || business&.subscription_discount_percentage
    return 0 unless discount_pct.present?

    (price * (discount_pct / 100.0)).round(2)
  end
  
  def subscription_savings_percentage
    return 0 if price.zero? || !subscription_enabled?
    ((subscription_discount_amount / price) * 100).round
  end
  
  def can_be_subscribed?
    active? && subscription_enabled? && in_stock?(1)
  end
  
  def subscription_display_price
    subscription_enabled? ? subscription_price : price
  end
  
  def subscription_display_savings
    return nil unless subscription_enabled? && business&.subscription_discount_percentage.present?
    "Save #{subscription_savings_percentage}% with subscription"
  end
  
  def allow_customer_preferences?
    # Allow customers to set preferences for subscription products
    subscription_enabled?
  end

  # ============================================
  # RENTAL METHODS
  # ============================================
  
  # Rental pricing - price field becomes daily_rate for rentals
  def daily_rate
    price
  end
  
  def daily_rate=(value)
    self.price = value
  end
  
  # Calculate rental price based on duration
  def calculate_rental_price(start_time, end_time, rate_type: nil)
    return nil unless rental?
    
    duration_mins = ((end_time - start_time) / 60).ceil
    duration_hours = (duration_mins / 60.0).ceil
    duration_days = (duration_hours / 24.0).ceil
    duration_weeks = (duration_days / 7.0).ceil
    
    # Auto-select optimal rate type if not specified
    rate_type ||= optimal_rental_rate_type(duration_hours)
    
    case rate_type.to_s
    when 'hourly'
      return nil unless allow_hourly_rental? && hourly_rate.present?
      { rate_type: 'hourly', rate: hourly_rate, quantity: duration_hours, total: (hourly_rate * duration_hours).round(2) }
    when 'weekly'
      return nil unless allow_weekly_rental? && weekly_rate.present?
      { rate_type: 'weekly', rate: weekly_rate, quantity: duration_weeks, total: (weekly_rate * duration_weeks).round(2) }
    else # daily
      return nil unless allow_daily_rental?
      { rate_type: 'daily', rate: daily_rate, quantity: duration_days, total: (daily_rate * duration_days).round(2) }
    end
  end
  
  # Select the best rate type based on duration
  def optimal_rental_rate_type(hours)
    return 'hourly' if hours < 8 && allow_hourly_rental? && hourly_rate.present?
    return 'weekly' if hours >= 168 && allow_weekly_rental? && weekly_rate.present?  # 7 days
    'daily'
  end
  
  MAX_RENTAL_DURATION_OPTIONS = 12
  WEEKDAY_NAMES = %w[monday tuesday wednesday thursday friday saturday sunday].freeze

  # ---------------------------------------------------------------------------
  # Rental duration helpers
  # ---------------------------------------------------------------------------

  def rental_duration_options=(value)
    normalized = Array(value).flat_map do |entry|
      if entry.is_a?(Hash)
        entry[:minutes] || entry['minutes']
      else
        entry
      end
    end

    normalized = normalized.map { |v| v.to_i }.select { |v| v.positive? }.uniq
    normalized = normalized.first(MAX_RENTAL_DURATION_OPTIONS)
    super(normalized)
  end

  def rental_duration_options
    super || []
  end

  def effective_rental_durations
    return rental_duration_options if rental_duration_options.present?

    base = min_rental_duration_mins.presence || default_rental_duration_mins
    max_duration = max_rental_duration_mins.presence || base
    return [base] if base >= max_duration

    step = base
    durations = []
    current = base
    while current <= max_duration
      durations << current
      current += step
    end
    durations
  end

  def default_rental_duration_mins
    return 60 if allow_hourly_rental?
    return (24.hours / 60).to_i if allow_daily_rental?

    60
  end

  # ---------------------------------------------------------------------------
  # Rental availability helpers
  # ---------------------------------------------------------------------------

  def rental_schedule_for(date)
    schedule = (rental_availability_schedule || {}).with_indifferent_access
    exceptions = schedule[:exceptions] || {}
    iso_date = date.iso8601

    slots = if exceptions.key?(iso_date)
              exceptions[iso_date]
            else
              day_key = date.strftime('%A').downcase
              schedule[day_key]
            end

    intervals = build_schedule_intervals_for(date, slots)
    return intervals if intervals.present?

    rental_availability_schedule.blank? ? full_day_intervals_for(date) : []
  end

  def rental_schedule_allows?(start_time, end_time)
    return true if rental_availability_schedule.blank?

    tz = business&.time_zone.presence || 'UTC'
    Time.use_zone(tz) do
      start_date = start_time.in_time_zone(tz).to_date
      end_date = end_time.in_time_zone(tz).to_date

      # Single-day rental: check that there's a slot covering the entire period
      if start_date == end_date
        intervals = rental_schedule_for(start_date)
        return false if intervals.blank?

        return intervals.any? do |slot|
          slot[:start] <= start_time && slot[:end] >= end_time
        end
      end

      # Multi-day rental: check each day in the rental period
      current_date = start_date

      while current_date <= end_date
        intervals = rental_schedule_for(current_date)
        return false if intervals.blank?

        if current_date == start_date
          # First day: ensure there's a slot that starts at or before the start_time
          has_valid_slot = intervals.any? { |slot| slot[:start] <= start_time }
          return false unless has_valid_slot
        elsif current_date == end_date
          # Last day: ensure there's a slot that ends at or after the end_time
          has_valid_slot = intervals.any? { |slot| slot[:end] >= end_time }
          return false unless has_valid_slot
        else
          # Middle days: just need to have availability (at least one slot exists)
          # intervals.blank? check above already handles this
        end

        current_date = current_date.next_day
      end

      true
    end
  end

  def rental_availability_schedule=(value)
    super(normalize_schedule_payload(value))
  end

  # Check rental availability for a time period
  def rental_available_for?(start_time, end_time, quantity: 1, exclude_booking_id: nil)
    return false unless rental?
    return false unless rental_schedule_allows?(start_time, end_time)

    available_rental_quantity(start_time, end_time, exclude_booking_id: exclude_booking_id) >= quantity
  end
  
  # Get available quantity for a time period
  def available_rental_quantity(start_time, end_time, exclude_booking_id: nil)
    return 0 unless rental?
    
    # Apply buffer time
    buffer = (rental_buffer_mins || business&.rental_buffer_mins || 0).minutes
    buffered_start = start_time - buffer
    buffered_end = end_time + buffer
    
    # Find overlapping bookings (not cancelled or completed)
    overlapping = rental_bookings
      .where.not(status: ['cancelled', 'completed'])
      .where('start_time < ? AND end_time > ?', buffered_end, buffered_start)
    
    overlapping = overlapping.where.not(id: exclude_booking_id) if exclude_booking_id
    
    booked_quantity = overlapping.sum(:quantity)
    [rental_quantity_available - booked_quantity, 0].max
  end
  
  # Generate rental availability calendar
  def rental_availability_calendar(start_date, end_date)
    return {} unless rental?
    
    calendar = {}
    (start_date..end_date).each do |date|
      day_start = date.in_time_zone(business&.time_zone || 'UTC').beginning_of_day
      day_end = date.in_time_zone(business&.time_zone || 'UTC').end_of_day
      
      available = available_rental_quantity(day_start, day_end)
      calendar[date.to_s] = {
        available: available,
        total: rental_quantity_available,
        fully_booked: available == 0
      }
    end
    calendar
  end
  
  # Validate rental duration constraints
  def valid_rental_duration?(start_time, end_time)
    return true unless rental?
    
    duration_mins = ((end_time - start_time) / 60).ceil
    
    if min_rental_duration_mins.present? && duration_mins < min_rental_duration_mins
      return false
    end
    
    if max_rental_duration_mins.present? && duration_mins > max_rental_duration_mins
      return false
    end
    
    true
  end
  
  # Display rental duration constraints
  def rental_duration_display
    return nil unless rental?
    
    parts = []
    if min_rental_duration_mins.present?
      parts << "Min: #{duration_in_words(min_rental_duration_mins)}"
    end
    if max_rental_duration_mins.present?
      parts << "Max: #{duration_in_words(max_rental_duration_mins)}"
    end
    parts.any? ? parts.join(' | ') : nil
  end
  
  # Get rental pricing display
  def rental_pricing_display
    return nil unless rental?
    
    prices = []
    prices << "#{ActionController::Base.helpers.number_to_currency(hourly_rate)}/hr" if allow_hourly_rental? && hourly_rate.present?
    prices << "#{ActionController::Base.helpers.number_to_currency(daily_rate)}/day" if allow_daily_rental?
    prices << "#{ActionController::Base.helpers.number_to_currency(weekly_rate)}/week" if allow_weekly_rental? && weekly_rate.present?
    prices.join(' • ')
  end
  
  # Variant label display logic
  def should_show_variant_selector?
    # Show selector when there are 2 or more total variants
    product_variants.count >= 2
  end
  
  def display_variant_label
    return 'Choose a variant' if variant_label_text.blank?
    variant_label_text
  end
  
  def user_created_variants
    product_variants.where.not(name: 'Default')
  end

  # Custom setter to handle nested image attributes (primary flags & ordering)
  def images_attributes=(attrs)
    return if attrs.blank?
    
    # Normalize to array of attribute hashes
    attrs_list = attrs.is_a?(Hash) ? attrs.values : Array(attrs)
    return if attrs_list.empty?

    # Store attributes for validation
    @pending_image_attributes = attrs_list

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

  # Position management
  scope :positioned, -> { order(:position, :created_at) }
  scope :by_position, -> { order(:position) }
  
  # Set position before creation if not set
  before_create :set_position_to_end, unless: :position?
  after_destroy :resequence_positions

  # Position management methods
  def move_to_position(new_position)
    return if position == new_position
    
    transaction do
      if new_position > position
        # Moving down: shift items up
        business.products.where(position: (position + 1)..new_position).update_all('position = position - 1')
      else
        # Moving up: shift items down
        business.products.where(position: new_position...position).update_all('position = position + 1')
      end
      
      update!(position: new_position)
    end
  end
  
  def move_to_top
    move_to_position(0)
  end
  
  def move_to_bottom
    move_to_position(business.products.maximum(:position) || 0)
  end

  private

  def normalize_schedule_payload(value)
    return {} if value.blank?

    schedule_hash = if value.is_a?(String)
                      JSON.parse(value) rescue {}
                    else
                      value
                    end

    schedule_hash = schedule_hash.deep_stringify_keys
    normalized = {}

    WEEKDAY_NAMES.each do |day|
      slots = schedule_hash[day]
      next unless slots.is_a?(Array)
      normalized[day] = slots.map { |slot| normalize_schedule_slot(slot) }.compact
    end

    if schedule_hash['exceptions'].is_a?(Hash)
      normalized['exceptions'] = {}
      schedule_hash['exceptions'].each do |date, slots|
        next unless slots.is_a?(Array)
        normalized['exceptions'][date.to_s] = slots.map { |slot| normalize_schedule_slot(slot) }.compact
      end
    end

    normalized
  end

  def normalize_schedule_slot(slot)
    return nil unless slot.is_a?(Hash)
    start_str = slot['start'] || slot[:start]
    end_str = slot['end'] || slot[:end]
    return nil if start_str.blank? || end_str.blank?
    { 'start' => start_str, 'end' => end_str }
  end

  def build_schedule_intervals_for(date, slots)
    tz = business&.time_zone.presence || 'UTC'
    Time.use_zone(tz) do
      Array(slots).filter_map do |slot|
        start_str = slot['start'] || slot[:start]
        end_str = slot['end'] || slot[:end]
        next if start_str.blank? || end_str.blank?
        begin
          start_time = Time.zone.parse("#{date} #{start_str}")
          end_time = Time.zone.parse("#{date} #{end_str}")
        rescue ArgumentError
          next
        end
        next unless start_time && end_time && end_time > start_time
        { start: start_time, end: end_time }
      end
    end
  end

  def full_day_intervals_for(date)
    tz = business&.time_zone.presence || 'UTC'
    Time.use_zone(tz) do
      start_time = date.in_time_zone.beginning_of_day
      end_time = date.in_time_zone.end_of_day
      [{ start: start_time, end: end_time }]
    end
  end

  def rental_duration_options_valid
    return if rental_duration_options.blank?

    unless rental_duration_options.is_a?(Array)
      errors.add(:rental_duration_options, 'must be a list of minute values')
      return
    end

    unless rental_duration_options.all? { |val| val.is_a?(Integer) && val.positive? }
      errors.add(:rental_duration_options, 'must contain positive minute values')
    end

    if rental_duration_options.size > MAX_RENTAL_DURATION_OPTIONS
      errors.add(:rental_duration_options, "cannot have more than #{MAX_RENTAL_DURATION_OPTIONS} options")
    end
  end

  def rental_schedule_structure
    return if rental_availability_schedule.blank?

    schedule = rental_availability_schedule.is_a?(Hash) ? rental_availability_schedule : {}
    WEEKDAY_NAMES.each do |day|
      next unless schedule[day].present?
      validate_schedule_slots_for(day, schedule[day])
    end

    if schedule['exceptions'].present? && schedule['exceptions'].is_a?(Hash)
      schedule['exceptions'].each do |date, slots|
        validate_schedule_slots_for(date, slots)
      end
    end
  end

  def validate_schedule_slots_for(key, slots)
    unless slots.is_a?(Array)
      errors.add(:rental_availability_schedule, "#{key} must be a list of time slots")
      return
    end

    slots.each do |slot|
      start_str = slot['start'] || slot[:start]
      end_str = slot['end'] || slot[:end]
      if start_str.blank? || end_str.blank?
        errors.add(:rental_availability_schedule, "#{key} slots must include start and end times")
        next
      end
      begin
        Tod::TimeOfDay.parse(start_str)
        Tod::TimeOfDay.parse(end_str)
      rescue ArgumentError
        errors.add(:rental_availability_schedule, "#{key} has invalid time format")
      end
    end
  end

  def min_rental_not_greater_than_max
    return unless min_rental_duration_mins.present? && max_rental_duration_mins.present?
    if min_rental_duration_mins > max_rental_duration_mins
      errors.add(:min_rental_duration_mins, 'cannot be greater than maximum rental duration')
    end
  end
  
  def rental_must_have_daily_rate
    if price.blank? || price <= 0
      errors.add(:price, 'is required for rentals (this is the daily rate)')
    end
  end

  def validate_pending_image_attributes
    return unless @pending_image_attributes
    
    validation_errors = validate_image_attributes(@pending_image_attributes)
    validation_errors.each { |error| errors.add(:images, error) }
    @pending_image_attributes = nil # Clear after validation
  end

  def validate_image_attributes(attrs_list)
    errors = []
    
    # Get IDs that aren't being destroyed
    image_ids = attrs_list
      .reject { |attrs| ActiveModel::Type::Boolean.new.cast(attrs[:_destroy]) }
      .map { |attrs| attrs[:id] }
      .compact
      .map(&:to_i)
    
    return errors if image_ids.empty?
    
    # Check for non-existent image IDs (only for non-deletion operations)
    existing_attachment_ids = images.attachments.pluck(:id)
    
    # Only validate existence for operations that require the image to exist
    # (like setting primary or position), not for deletions which should be graceful
    non_deletion_attrs = attrs_list.reject { |attrs| ActiveModel::Type::Boolean.new.cast(attrs[:_destroy]) }
    has_deletions = attrs_list.any? { |attrs| ActiveModel::Type::Boolean.new.cast(attrs[:_destroy]) }
    
    non_deletion_attrs.each do |attrs|
      id = attrs[:id].to_i
      next unless id > 0 # Skip invalid IDs
      
      unless existing_attachment_ids.include?(id)
        # Only error if we're trying to set properties on a non-existent image
        # But be more forgiving in mixed operations (deletion + other operations)
        if (attrs.key?(:primary) || attrs.key?(:position)) && !has_deletions
          errors << "Image must exist"
          break
        end
      end
    end
    
    # Check for duplicate image IDs
    if image_ids.uniq.length != image_ids.length
      errors << "Image IDs must be unique"
    end
    
    # Check if we're trying to reorder images and have all image IDs
    # Only validate completeness if NO images are being destroyed (pure reordering)
    being_destroyed = attrs_list.any? { |attrs| ActiveModel::Type::Boolean.new.cast(attrs[:_destroy]) }
    positions = attrs_list
      .reject { |attrs| ActiveModel::Type::Boolean.new.cast(attrs[:_destroy]) }
      .map { |attrs| attrs[:position] }
      .compact
    
    if positions.any? && !being_destroyed && image_ids.sort != existing_attachment_ids.sort
      errors << "Image IDs are incomplete"
    end
    
    # Check if image IDs belong to this product
    image_ids.each do |id|
      attachment = ActiveStorage::Attachment.find_by(id: id)
      if attachment && attachment.record != self
        errors << "Image must belong to the product"
        break
      end
    end
    
    errors
  end

  def image_size_validation
    images.each do |image|
      if image.blob.byte_size > 15.megabytes
        errors.add(:images, "must be less than 15MB")
      end
    end
  end
  
  def image_format_validation
    images.each do |image|
      unless FileUploadSecurity.valid_image_type?(image.blob.content_type)
        errors.add(:images, FileUploadSecurity.image_validation_options[:content_type][:message])                                                                 
      end
    end
  end

  def process_images
    images.each do |image|
      # Create optimized variants after upload in background
      ProcessImageJob.perform_later(image.id)
    end
  end

  def create_default_variant
    return if product_variants.exists?
    # Use the product's stock_quantity for the default variant stock
    product_variants.create!(
      name:  'Default',
      sku:   "default-#{id}",
      price_modifier: 0,
      stock_quantity: stock_quantity || 0
    )
  end

  def set_position_to_end
    max_position = business&.products&.maximum(:position) || -1
    self.position = max_position + 1
  end
  
  def resequence_positions
    business.products.where('position > ?', position).update_all('position = position - 1')
  end

  # Use shared validation from PriceDurationParser
end 