class ProcessGalleryPhotoJob < ApplicationJob
  queue_as :default

  def perform(gallery_photo_id)
    gallery_photo = GalleryPhoto.find(gallery_photo_id)
    attachment = gallery_photo.image

    return unless attachment.attached?

    blob = attachment.blob

    # Convert HEIC to JPEG if needed - MUST happen before variant generation
    if FileUploadSecurity.heic_format?(blob.content_type)
      convert_heic_to_jpeg(attachment)
      # Reload attachment after conversion and verify it succeeded
      attachment.reload
      begin
        blob = attachment.blob
      rescue ActiveRecord::RecordNotFound => e
        Rails.logger.error "[GALLERY_PHOTO_PROCESSING] Attachment or blob not found after HEIC conversion: #{e.message}"
        return
      end
      return unless blob
    end

    # Always generate variants for images
    if blob.image?
      generate_variants(attachment)
    end
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "Gallery photo #{gallery_photo_id} not found: #{e.message}"
  rescue => e
    Rails.logger.error "Failed to process gallery photo #{gallery_photo_id}: #{e.message}"
  end

  private

  def convert_heic_to_jpeg(attachment)
    old_blob = attachment.blob

    Rails.logger.info "[GALLERY_HEIC_CONVERSION] Converting HEIC image #{attachment.id} to JPEG"

    # Check if ImageMagick supports HEIC
    unless heic_supported?
      Rails.logger.warn "[GALLERY_HEIC_CONVERSION] ImageMagick does not support HEIC format, keeping original"
      return
    end

    # Convert HEIC to JPEG
    new_blob = nil
    old_blob.open do |tempfile|
      converted = ImageProcessing::MiniMagick
        .source(tempfile)
        .auto_orient
        .strip
        .colorspace('sRGB')
        .saver(quality: 92)
        .convert("jpeg")
        .call

      # Create new blob with converted JPEG content
      File.open(converted) do |converted_file|
        new_blob = ActiveStorage::Blob.create_and_upload!(
          io: converted_file,
          filename: old_blob.filename.to_s.gsub(/\.(heic|heif|heic-sequence|heif-sequence)$/i, '.jpg'),
          content_type: 'image/jpeg'
        )

        # Update attachment to point to new blob
        attachment.update!(blob: new_blob)

        # Clean up old HEIC blob
        begin
          old_blob.purge_later
        rescue ActiveRecord::RecordNotFound
          Rails.logger.info "[GALLERY_HEIC_CONVERSION] Old blob already purged: #{old_blob.key}"
        end
      end
    end

    Rails.logger.info "[GALLERY_HEIC_CONVERSION] Successfully converted HEIC to JPEG: #{new_blob.filename}" if new_blob
  rescue ImageProcessing::Error => e
    Rails.logger.error "[GALLERY_HEIC_CONVERSION] HEIC conversion failed: #{e.message}"
    # Keep original HEIC - browser may not display but file is preserved
  rescue => e
    Rails.logger.error "[GALLERY_HEIC_CONVERSION] Unexpected error during HEIC conversion: #{e.message}"
  end

  def generate_variants(attachment)
    # Generate gallery-specific variants
    # Large variant for lightbox/fullscreen view
    attachment.variant(resize_to_limit: [1920, 1920], quality: 90).processed

    # Medium variant for gallery grid
    attachment.variant(resize_to_limit: [800, 800], quality: 85).processed

    # Small variant for thumbnails
    attachment.variant(resize_to_limit: [400, 400], quality: 80).processed

    Rails.logger.info "[GALLERY_PHOTO_PROCESSING] Generated variants for gallery photo attachment #{attachment.id}"
  end

  def heic_supported?
    @heic_supported ||= begin
      output = `convert -list format 2>/dev/null`
      output.include?('HEIC') || output.include?('HEIF')
    rescue => e
      Rails.logger.warn "[GALLERY_HEIC_CONVERSION] Could not check ImageMagick format support: #{e.message}"
      false
    end
  end
end
