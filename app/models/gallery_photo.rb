# frozen_string_literal: true

# == Schema Information
#
# Table name: gallery_photos
#
#  id                    :bigint           not null, primary key
#  business_id           :bigint           not null
#  title                 :string
#  description           :text
#  position              :integer          not null
#  photo_source          :integer          default("gallery"), not null
#  source_type           :string
#  source_id             :integer
#  source_attachment_id  :integer
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#

class GalleryPhoto < ApplicationRecord
  # Enums
  enum :photo_source, {
    gallery: 0,      # Photo uploaded directly to gallery
    service: 1,      # Photo from a service
    product: 2       # Photo from a product
  }, prefix: true

  # Associations
  belongs_to :business
  belongs_to :source, polymorphic: true, optional: true

  # ActiveStorage for gallery-uploaded photos
  has_one_attached :image

  # Validations
  validates :position, presence: true,
                       uniqueness: { scope: :business_id },
                       numericality: { only_integer: true, greater_than: 0 }

  validates :photo_source, presence: true

  # Validate that business doesn't exceed 100 photos
  validate :max_photos_per_business, on: :create

  # Validate that photo has either attached image or source reference
  validate :has_photo_source

  # Validate image size and format for gallery photos
  validate :validate_image_attachment, if: -> { photo_source_gallery? && image.attached? }

  # Scopes
  scope :by_position, -> { order(:position) }
  scope :gallery_uploads, -> { where(photo_source: :gallery) }
  scope :from_services, -> { where(photo_source: :service) }
  scope :from_products, -> { where(photo_source: :product) }

  # Callbacks
  before_validation :acquire_lock_and_set_position, on: :create, if: -> { position.blank? }
  after_destroy :reorder_positions
  after_commit :process_image_async, on: [:create, :update], if: :should_process_image?

  # Instance Methods

  # Get the image URL for the specified variant
  # @param variant [Symbol] :thumb, :medium, or :large
  # @return [String] URL to the image variant
  def image_url(variant = :medium)
    if photo_source_gallery? && image.attached?
      Rails.application.routes.url_helpers.rails_blob_path(image.variant(variant_options(variant)), only_path: true)
    elsif photo_source_service? || photo_source_product?
      fetch_source_image_url(variant)
    end
  rescue StandardError => e
    Rails.logger.error("GalleryPhoto#image_url error: #{e.message}")
    nil
  end

  # Check if photo has a valid image source
  # @return [Boolean]
  def has_image?
    (photo_source_gallery? && image.attached?) ||
      (photo_source_service? && source_attachment_id.present?) ||
      (photo_source_product? && source_attachment_id.present?)
  end

  # Reorder this photo to a new position
  # @param new_position [Integer] The new position (1-based)
  def reorder(new_position)
    return if position == new_position

    transaction do
      ordered_ids = business.gallery_photos.order(:position).lock.pluck(:id)
      ordered_ids.delete(id)
      ordered_ids.insert(new_position - 1, id)

      ordered_ids.each_with_index do |photo_id, index|
        business.gallery_photos.where(id: photo_id).update_all(position: -(index + 1))
      end

      ordered_ids.each_with_index do |photo_id, index|
        business.gallery_photos.where(id: photo_id).update_all(position: index + 1)
      end
    end
  end

  private

  def should_process_image?
    return false unless photo_source_gallery?

    saved_change_to_attribute?(:id) || image_attachment_previously_changed?
  end

  def image_attachment_previously_changed?
    attachment = image_attachment
    return false unless attachment

    changes = attachment.previous_changes
    return false if changes.blank?

    (changes.key?('id') && changes['id'].present?) ||
      (changes.key?('blob_id') && changes['blob_id'].present?)
  end

  # Acquire a row-level lock on the business record, then set the next position.
  # This prevents race conditions where two concurrent requests could:
  # 1. Both see the same max position and create duplicates
  # 2. Both pass the max_photos validation when at 99 photos
  #
  # The lock is held for the duration of the save transaction, ensuring
  # atomicity of both the count check (in validation) and position assignment.
  def acquire_lock_and_set_position
    return unless business

    # Acquire a row-level lock on the business record
    # This ensures only one gallery photo can be created at a time per business
    business.lock!

    # Now safely get the next position with the lock held
    max_position = business.gallery_photos.maximum(:position) || 0
    self.position = max_position + 1
  end

  # Reorder positions after deletion to maintain sequence
  def reorder_positions
    business.gallery_photos.where("position > ?", position)
            .update_all("position = position - 1")
  end

  # Validate max 100 photos per business
  # Uses pessimistic locking to prevent race conditions where concurrent requests
  # could both see 99 photos and both create a new one, exceeding the limit.
  # The lock is acquired on the business record, ensuring only one photo
  # creation can proceed at a time per business.
  def max_photos_per_business
    return unless business

    # Acquire a row-level lock on the business record for accurate count
    # This is safe to call even if acquire_lock_and_set_position already
    # acquired the lock - subsequent lock! calls in the same transaction are no-ops
    business.lock!

    if business.gallery_photos.count >= 100
      errors.add(:base, "Maximum 100 photos allowed per gallery")
    end
  end

  # Validate that photo has either attached image or source reference
  def has_photo_source
    if photo_source_gallery? && !image.attached?
      errors.add(:image, "must be attached for gallery photos")
    elsif (photo_source_service? || photo_source_product?) && source_attachment_id.blank?
      errors.add(:source_attachment_id, "must be present for service/product photos")
    end
  end

  # Validate image attachment size and format
  def validate_image_attachment
    return unless image.attached?

    # Max 15MB
    if image.blob.byte_size > 15.megabytes
      errors.add(:image, "size must be less than 15MB")
    end

    # Allowed formats
    allowed_formats = %w[image/jpeg image/jpg image/png image/gif image/webp image/heic image/heif]
    unless allowed_formats.include?(image.blob.content_type)
      errors.add(:image, "must be a JPEG, PNG, GIF, WebP, or HEIC file")
    end
  end

  # Get variant options for image processing
  # @param variant [Symbol] :thumb, :medium, or :large
  # @return [Hash] Variant processing options
  def variant_options(variant)
    case variant
    when :thumb
      { resize_to_fill: [400, 300], format: :webp }
    when :medium
      { resize_to_fill: [1200, 900], format: :webp }
    when :large
      { resize_to_limit: [2000, 2000], format: :webp }
    else
      { resize_to_fill: [1200, 900], format: :webp }
    end
  end

  # Fetch image URL from service or product source
  # @param variant [Symbol] :thumb, :medium, or :large
  # @return [String, nil] URL to the source image
  def fetch_source_image_url(variant)
    return nil unless source_attachment_id.present?

    attachment = ActiveStorage::Attachment.find_by(id: source_attachment_id)
    return nil unless attachment&.blob

    Rails.application.routes.url_helpers.rails_blob_path(
      attachment.variant(variant_options(variant)),
      only_path: true
    )
  rescue StandardError => e
    Rails.logger.error("GalleryPhoto#fetch_source_image_url error: #{e.message}")
    nil
  end

  # Trigger background job to process gallery photo image
  def process_image_async
    return unless image.attached?

    ProcessGalleryPhotoJob.perform_later(id)
  end
end
