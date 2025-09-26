# app/models/product.rb
class Product < ApplicationRecord
  # Assuming TenantScoped concern handles belongs_to :business and default scoping
  include TenantScoped

  has_many :product_variants, dependent: :destroy
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

  enum :product_type, { standard: 0, service: 1, mixed: 2 }

  include PriceDurationParser

  validates :name, presence: true, uniqueness: { scope: :business_id }
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
    # Include basic fields, foreign keys, flags, and timestamps
    %w[id name description price active featured business_id created_at updated_at product_type allow_discounts show_stock_to_customers hide_when_out_of_stock variant_label_text]
  end

  def self.ransackable_associations(auth_object = nil)
    # Allowlist associations for searching/filtering in ActiveAdmin
    %w[business product_variants line_items images_attachments images_blobs product_service_add_ons add_on_services]
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