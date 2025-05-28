# frozen_string_literal: true

class Service < ApplicationRecord
  include TenantScoped
  
  acts_as_tenant(:business)
  belongs_to :business
  has_many :staff_assignments, dependent: :destroy
  has_many :assigned_staff, through: :staff_assignments, source: :user
  has_many :services_staff_members, dependent: :destroy
  has_many :staff_members, through: :services_staff_members
  has_many :bookings, dependent: :destroy
  
  # Add-on products association
  has_many :product_service_add_ons, dependent: :destroy
  has_many :add_on_products, through: :product_service_add_ons, source: :product
  
  # Image attachments
  has_many_attached :images

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
  before_destroy :orphan_bookings
  
  validates :name, presence: true
  validates :name, uniqueness: { scope: :business_id }
  validates :duration, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :active, inclusion: { in: [true, false] }
  validates :business_id, presence: true

  # Validations for images
  validates :images, content_type: ['image/png', 'image/jpeg'], size: { less_than: 5.megabytes }
  
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
  
  # Optional: Define an enum for duration if you have standard lengths
  # enum duration_minutes: { thirty_minutes: 30, sixty_minutes: 60, ninety_minutes: 90 }
  
  # Define ransackable attributes for ActiveAdmin
  def self.ransackable_attributes(auth_object = nil)
    %w[id name description duration price active business_id created_at updated_at featured service_type min_bookings max_bookings spots]
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

  # Custom setter to handle nested image attributes (primary flags & ordering)
  # This logic is adapted from the Product model and assumes similar ActiveAdmin handling
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
      errors.add(:images, "Image must belong to the service")
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

  def primary_image
     # Return the primary image if marked, otherwise nil
     images.attachments.order(:position).find_by(primary: true)
  end

  # Methods for setting primary image and reordering (optional, might be handled by images_attributes= setter)
  # def set_primary_image(image)
  #   images.attachments.update_all(primary: false)
  #   image.update(primary: true)
  # end

  # def reorder_images(order_ids)
  #   order_ids.each_with_index do |id, index|
  #     images.attachments.find(id).update(position: index)
  #   end
  # end

  private

  def set_initial_spots
    # For 'Experience' services, initialize spots with max_bookings if not already set
    self.spots = max_bookings if spots.nil? && max_bookings.present?
  end

  def orphan_bookings
    # Mark all associated bookings as business_deleted and remove associations
    ActsAsTenant.without_tenant do
      bookings.find_each do |booking|
        booking.mark_business_deleted!
      end
    end
  end
end 