# frozen_string_literal: true

# Service class for managing gallery photos
# Handles photo uploads, featuring, reordering, and hybrid references to service/product images
class GalleryPhotoService
  class MaxPhotosExceededError < StandardError; end
  class MaxFeaturedPhotosExceededError < StandardError; end
  class PhotoNotFoundError < StandardError; end

  # Add a new photo from upload
  # @param business [Business] The business to add the photo to
  # @param file [ActionDispatch::Http::UploadedFile] The uploaded photo file
  # @param attributes [Hash] Additional attributes (title, description, featured, display_in_hero)
  # @return [GalleryPhoto] The created gallery photo
  # @raise [MaxPhotosExceededError] if business already has 100 photos
  def self.add_from_upload(business, file, attributes = {})
    raise MaxPhotosExceededError, "Maximum 100 photos allowed per gallery" if business.gallery_photos.count >= 100

    gallery_photo = business.gallery_photos.build(
      photo_source: :gallery,
      title: attributes[:title],
      description: attributes[:description],
      featured: attributes[:featured] || false,
      display_in_hero: attributes[:display_in_hero] || false
    )

    gallery_photo.image.attach(file)

    if gallery_photo.save
      Rails.logger.info "GalleryPhoto created for business #{business.id}: #{gallery_photo.id}"
      gallery_photo
    else
      Rails.logger.error "Failed to create GalleryPhoto for business #{business.id}: #{gallery_photo.errors.full_messages.join(', ')}"
      raise ActiveRecord::RecordInvalid, gallery_photo
    end
  end

  # Add a photo reference from existing service/product image
  # @param business [Business] The business to add the photo to
  # @param source_type [String] 'Service' or 'Product'
  # @param source_id [Integer] ID of the service or product
  # @param attachment_id [Integer] ID of the ActiveStorage attachment
  # @param attributes [Hash] Additional attributes (title, description, featured, display_in_hero)
  # @return [GalleryPhoto] The created gallery photo
  # @raise [MaxPhotosExceededError] if business already has 100 photos
  def self.add_from_existing(business, source_type, source_id, attachment_id, attributes = {})
    raise MaxPhotosExceededError, "Maximum 100 photos allowed per gallery" if business.gallery_photos.count >= 100

    # Validate that the source exists and belongs to the business
    source = source_type.constantize.find(source_id)
    raise ArgumentError, "Source does not belong to this business" unless source.business_id == business.id

    # Validate that the attachment exists and belongs to the source
    attachment = ActiveStorage::Attachment.find(attachment_id)
    raise ArgumentError, "Attachment does not belong to source" unless attachment.record_id == source_id && attachment.record_type == source_type

    photo_source_enum = source_type.downcase.to_sym # :service or :product

    gallery_photo = business.gallery_photos.create!(
      photo_source: photo_source_enum,
      source_type: source_type,
      source_id: source_id,
      source_attachment_id: attachment_id,
      title: attributes[:title] || source.name,
      description: attributes[:description],
      featured: attributes[:featured] || false,
      display_in_hero: attributes[:display_in_hero] || false
    )

    Rails.logger.info "GalleryPhoto created from #{source_type} for business #{business.id}: #{gallery_photo.id}"
    gallery_photo
  end

  # Toggle featured status of a photo
  # @param gallery_photo [GalleryPhoto] The photo to toggle
  # @return [Boolean] Success status
  # @raise [MaxFeaturedPhotosExceededError] if trying to feature a 6th photo
  def self.toggle_featured(gallery_photo)
    if gallery_photo.featured?
      gallery_photo.update!(featured: false)
      Rails.logger.info "GalleryPhoto #{gallery_photo.id} unfeatured"
      true
    else
      featured_count = gallery_photo.business.gallery_photos.where(featured: true).where.not(id: gallery_photo.id).count

      if featured_count >= 5
        raise MaxFeaturedPhotosExceededError, "Maximum 5 photos can be featured. Please unfeature another photo first."
      end

      gallery_photo.update!(featured: true)
      Rails.logger.info "GalleryPhoto #{gallery_photo.id} featured"
      true
    end
  end

  # Reorder photos in bulk
  # @param business [Business] The business whose photos to reorder
  # @param photo_ids_array [Array<Integer>] Array of photo IDs in desired order
  # @return [Boolean] Success status
  def self.reorder(business, photo_ids_array)
    return false if photo_ids_array.blank?

    ActiveRecord::Base.transaction do
      photo_ids_array.each_with_index do |photo_id, index|
        photo = business.gallery_photos.find(photo_id)
        new_position = index + 1
        photo.update_column(:position, new_position) if photo.position != new_position
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
  # @param attributes [Hash] Attributes to update (title, description, featured, display_in_hero)
  # @return [Boolean] Success status
  def self.update_photo(gallery_photo, attributes)
    # Handle featured status separately to enforce limit
    if attributes.key?(:featured) && attributes[:featured] != gallery_photo.featured?
      toggle_featured(gallery_photo)
      attributes = attributes.except(:featured)
    end

    if gallery_photo.update(attributes)
      Rails.logger.info "GalleryPhoto #{gallery_photo.id} updated"
      true
    else
      Rails.logger.error "Failed to update GalleryPhoto #{gallery_photo.id}: #{gallery_photo.errors.full_messages.join(', ')}"
      false
    end
  rescue MaxFeaturedPhotosExceededError => e
    gallery_photo.errors.add(:featured, e.message)
    false
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
          thumbnail_url: Rails.application.routes.url_helpers.url_for(attachment.variant(resize_to_limit: [200, 200]))
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
          thumbnail_url: Rails.application.routes.url_helpers.url_for(attachment.variant(resize_to_limit: [200, 200]))
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
