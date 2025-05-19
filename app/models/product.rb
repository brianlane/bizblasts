# app/models/product.rb
class Product < ApplicationRecord
  # Assuming TenantScoped concern handles belongs_to :business and default scoping
  include TenantScoped

  belongs_to :category, optional: true
  has_many :product_variants, dependent: :destroy
  # If variants are mandatory, line_items might associate through variants
  # has_many :line_items, dependent: :destroy # Use this if products DON'T have variants
  has_many :line_items, through: :product_variants # Use this if products MUST have variants

  has_many_attached :images

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

  enum :product_type, { standard: 0, service: 1, mixed: 2 }

  validates :name, presence: true, uniqueness: { scope: :business_id }
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  # Validate attachments using built-in ActiveStorage validators
  validates :images, content_type: ['image/png', 'image/jpeg'], size: { less_than: 5.megabytes }

  # TODO: Add method or validation for primary image designation if needed
  # TODO: Add method for image ordering if needed

  scope :active, -> { where(active: true) }
  scope :featured, -> { where(featured: true) }

  # Allows creating variants directly when creating/updating a product
  accepts_nested_attributes_for :product_variants, allow_destroy: true

  # Ensure products without explicit variants have a default variant for cart operations
  after_create :create_default_variant

  # --- Add Ransack methods --- 
  def self.ransackable_attributes(auth_object = nil)
    # Allowlist attributes for searching/filtering in ActiveAdmin
    # Include basic fields, foreign keys, flags, and timestamps
    %w[id name description price active featured category_id business_id created_at updated_at product_type]
  end

  def self.ransackable_associations(auth_object = nil)
    # Allowlist associations for searching/filtering in ActiveAdmin
    %w[business category product_variants line_items images_attachments images_blobs product_service_add_ons add_on_services]
  end
  # --- End Ransack methods ---

  # Delegate stock check to variants if they exist, otherwise check product stock
  def in_stock?(requested_quantity = 1)
    if product_variants.any?
      product_variants.sum(:stock_quantity) >= requested_quantity
    else
      stock_quantity >= requested_quantity
    end
  end

  # If products can be sold without variants, add stock field and validation
  validates :stock_quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, unless: :has_variants?

  def has_variants?
    product_variants.exists?  
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

  # Custom setter to handle nested image attributes (primary flags & ordering)
  def images_attributes=(attrs)
    # Normalize to array
    attrs_list = attrs.is_a?(Hash) ? attrs.values : Array(attrs)

    # Primary-only update if no positions are provided
    unless attrs_list.any? { |h| h.key?(:position) }
      # Expect exactly one record for primary-only
      if attrs_list.size != 1
        errors.add(:images, "Image IDs are incomplete")
        return
      end
      data = attrs_list.first
      id = data[:id].to_i
      # Must exist globally
      unless ActiveStorage::Attachment.exists?(id)
        errors.add(:images, "Image must exist")
        return
      end
      # Unset all, then set primary
      images.update_all(primary: false)
      images.find(id).update(primary: ActiveModel::Type::Boolean.new.cast(data[:primary]))
      return
    end

    # Reorder and primary simultaneous flow
    current_ids = images.pluck(:id)
    attrs_count = attrs_list.size
    # Must provide full set for reorder
    if attrs_count != current_ids.size
      errors.add(:images, "Image IDs are incomplete")
      return
    end
    provided_ids = attrs_list.map { |h| h[:id].to_i }
    # Global existence check
    missing_global = provided_ids.reject { |i| ActiveStorage::Attachment.exists?(i) }
    if missing_global.any?
      errors.add(:images, "Image must exist")
      return
    end
    # Belonging check
    extra_ids = provided_ids - current_ids
    if extra_ids.any?
      errors.add(:images, "Image must belong to the product")
      return
    end
    # Uniqueness
    if provided_ids.uniq.size != provided_ids.size
      errors.add(:images, "Image IDs must be unique")
      return
    end

    # Process each attribute
    attrs_list.each do |h|
      id = h[:id].to_i
      attachment = images.find(id)
      # Purge if requested
      if ActiveModel::Type::Boolean.new.cast(h[:_destroy])
        attachment.purge
        next
      end
      # Apply primary and position updates
      changes = {}
      changes[:primary] = ActiveModel::Type::Boolean.new.cast(h[:primary]) if h.key?(:primary)
      changes[:position] = h[:position] if h.key?(:position)
      attachment.update(changes) if changes.any?
    end
  end

  private

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
end 