# frozen_string_literal: true

# Service class for managing gallery photos
# Handles photo uploads, reordering, and hybrid references to service/product images
class GalleryPhotoService
  class MaxPhotosExceededError < StandardError; end
  class PhotoNotFoundError < StandardError; end

  # Allowed source types to prevent code injection via constantize
  ALLOWED_SOURCE_TYPES = %w[Service Product].freeze

  # Add a new photo from upload
  # @param business [Business] The business to add the photo to
  # @param file [ActionDispatch::Http::UploadedFile] The uploaded photo file
  # @param attributes [Hash] Additional attributes (title, description)
  # @return [GalleryPhoto] The created gallery photo
  # @raise [MaxPhotosExceededError] if business already has 100 photos
  def self.add_from_upload(business, file, attributes = {})
    gallery_photo = nil

    # Use transaction with lock to prevent race conditions
    ActiveRecord::Base.transaction do
      # Lock the business record to prevent concurrent photo creation
      locked_business = Business.lock.find(business.id)

      # Check photo count limit with lock held
      if locked_business.gallery_photos.count >= 100
        raise MaxPhotosExceededError, "Maximum 100 photos allowed per gallery"
      end

      gallery_photo = locked_business.gallery_photos.build(
        photo_source: :gallery,
        title: attributes[:title],
        description: attributes[:description]
      )

      gallery_photo.image.attach(file)

      if gallery_photo.save
        Rails.logger.info "GalleryPhoto created for business #{locked_business.id}: #{gallery_photo.id}"
      else
        Rails.logger.error "Failed to create GalleryPhoto for business #{locked_business.id}: #{gallery_photo.errors.full_messages.join(', ')}"
        raise ActiveRecord::RecordInvalid, gallery_photo
      end
    end

    gallery_photo
  end

  # Add a photo reference from existing service/product image
  # @param business [Business] The business to add the photo to
  # @param source_type [String] 'Service' or 'Product'
  # @param source_id [Integer] ID of the service or product
  # @param attachment_id [Integer] ID of the ActiveStorage attachment
  # @param attributes [Hash] Additional attributes (title, description)
  # @return [GalleryPhoto] The created gallery photo
  # @raise [MaxPhotosExceededError] if business already has 100 photos
  def self.add_from_existing(business, source_type, source_id, attachment_id, attributes = {})
    # Validate source_type to prevent code injection
    raise ArgumentError, "Invalid source_type. Must be one of: #{ALLOWED_SOURCE_TYPES.join(', ')}" unless ALLOWED_SOURCE_TYPES.include?(source_type)

    # Validate that the source exists and belongs to the business
    source = source_type.constantize.find(source_id)
    raise ArgumentError, "Source does not belong to this business" unless source.business_id == business.id

    # Validate that the attachment exists and belongs to the source
    attachment = ActiveStorage::Attachment.find(attachment_id)
    raise ArgumentError, "Attachment does not belong to source" unless attachment.record_id == source.id && attachment.record_type == source_type

    photo_source_enum = source_type.downcase.to_sym # :service or :product
    gallery_photo = nil

    # Use transaction with lock to prevent race conditions
    ActiveRecord::Base.transaction do
      # Lock the business record to prevent concurrent photo creation
      locked_business = Business.lock.find(business.id)

      # Check photo count limit with lock held
      if locked_business.gallery_photos.count >= 100
        raise MaxPhotosExceededError, "Maximum 100 photos allowed per gallery"
      end

      gallery_photo = locked_business.gallery_photos.create!(
        photo_source: photo_source_enum,
        source_type: source_type,
        source_id: source_id,
        source_attachment_id: attachment_id,
        title: attributes[:title] || source.name,
        description: attributes[:description]
      )

      Rails.logger.info "GalleryPhoto created from #{source_type} for business #{locked_business.id}: #{gallery_photo.id}"
    end

    gallery_photo
  end

  # Reorder photos in bulk
  # @param business [Business] The business whose photos to reorder
  # @param photo_ids_array [Array<Integer>] Array of photo IDs in desired order
  # @return [Boolean] Success status
  def self.reorder(business, photo_ids_array)
    return false if photo_ids_array.blank?

    ordered_ids = Array(photo_ids_array).map(&:to_i)
    return false if ordered_ids.empty?

    if ordered_ids.uniq.length != ordered_ids.length
      raise ArgumentError, "Duplicate photo IDs are not allowed"
    end

    ActiveRecord::Base.transaction do
      # Lock all photos for this business to prevent concurrent reorders from conflicting
      locked_photos = business.gallery_photos.order(:position).lock.to_a
      photos_by_id = locked_photos.index_by(&:id)
      current_ids = locked_photos.map(&:id)

      missing_ids = ordered_ids - current_ids
      if missing_ids.any?
        raise PhotoNotFoundError, "Photos #{missing_ids.join(', ')} do not belong to business #{business.id}"
      end

      # Preserve the relative order of any photos not explicitly passed in
      remaining_ids = current_ids - ordered_ids
      final_order = ordered_ids + remaining_ids

      # Use a high positive offset so validations remain satisfied while we reshuffle
      max_position = locked_photos.map(&:position).compact.max || 0
      offset = max_position + final_order.size + 5

      final_order.each_with_index do |photo_id, index|
        temp_position = offset + index + 1
        photos_by_id.fetch(photo_id).update!(position: temp_position)
      end

      final_order.each_with_index do |photo_id, index|
        photos_by_id.fetch(photo_id).update!(position: index + 1)
      end
    end

    Rails.logger.info "Gallery photos reordered for business #{business.id}"
    true
  rescue StandardError => e
    Rails.logger.error "Failed to reorder gallery photos for business #{business.id}: #{e.message}"
    false
  end

  # Remove a gallery photo
  # @param gallery_photo [GalleryPhoto] The photo to remove
  # @return [Boolean] Success status
  def self.remove(gallery_photo)
    business_id = gallery_photo.business_id
    photo_id = gallery_photo.id

    if gallery_photo.destroy
      Rails.logger.info "GalleryPhoto #{photo_id} removed from business #{business_id}"
      true
    else
      Rails.logger.error "Failed to remove GalleryPhoto #{photo_id}: #{gallery_photo.errors.full_messages.join(', ')}"
      false
    end
  end

  # Update gallery photo attributes
  # @param gallery_photo [GalleryPhoto] The photo to update
  # @param attributes [Hash] Attributes to update (title, description)
  # @return [Boolean] Success status
  def self.update_photo(gallery_photo, attributes)
    if gallery_photo.update(attributes)
      Rails.logger.info "GalleryPhoto #{gallery_photo.id} updated"
      true
    else
      Rails.logger.error "Failed to update GalleryPhoto #{gallery_photo.id}: #{gallery_photo.errors.full_messages.join(', ')}"
      false
    end
  end

  # Get available service/product images that can be added to gallery
  # @param business [Business] The business
  # @return [Hash] Hash with :services and :products arrays, each containing image info
  def self.available_images_for_gallery(business)
    {
      services: fetch_service_images(business),
      products: fetch_product_images(business)
    }
  end

  private

  # Fetch service images not already in gallery
  # @param business [Business]
  # @return [Array<Hash>] Array of service image hashes
  def self.fetch_service_images(business)
    business.services.with_attached_images.flat_map do |service|
      service.images.attachments.map do |attachment|
        next if gallery_has_attachment?(business, 'Service', service.id, attachment.id)

        {
          source_type: 'Service',
          source_id: service.id,
          source_name: service.name,
          attachment_id: attachment.id,
          attachment_filename: attachment.filename.to_s,
          thumbnail_url: Rails.application.routes.url_helpers.rails_representation_path(attachment.variant(resize_to_limit: [200, 200]), only_path: true)
        }
      end.compact
    end
  end

  # Fetch product images not already in gallery
  # @param business [Business]
  # @return [Array<Hash>] Array of product image hashes
  def self.fetch_product_images(business)
    business.products.with_attached_images.flat_map do |product|
      product.images.attachments.map do |attachment|
        next if gallery_has_attachment?(business, 'Product', product.id, attachment.id)

        {
          source_type: 'Product',
          source_id: product.id,
          source_name: product.name,
          attachment_id: attachment.id,
          attachment_filename: attachment.filename.to_s,
          thumbnail_url: Rails.application.routes.url_helpers.rails_representation_path(attachment.variant(resize_to_limit: [200, 200]), only_path: true)
        }
      end.compact
    end
  end

  # Check if attachment is already in gallery
  # @param business [Business]
  # @param source_type [String]
  # @param source_id [Integer]
  # @param attachment_id [Integer]
  # @return [Boolean]
  def self.gallery_has_attachment?(business, source_type, source_id, attachment_id)
    business.gallery_photos.exists?(
      source_type: source_type,
      source_id: source_id,
      source_attachment_id: attachment_id
    )
  end
end
