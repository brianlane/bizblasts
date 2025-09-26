class ProcessImageJob < ApplicationJob
  queue_as :default

  def perform(image_attachment_id)
    attachment = ActiveStorage::Attachment.find(image_attachment_id)
    blob = attachment.blob

    # Convert HEIC to JPEG if needed - MUST happen before variant generation
    if FileUploadSecurity.heic_format?(blob.content_type)
      convert_heic_to_jpeg(attachment)
      # Reload attachment after conversion and verify it succeeded
      attachment.reload
      blob = attachment.blob rescue nil
      return unless blob
    end

    # Only process if it's an image and larger than 2MB
    if blob.image? && blob.byte_size > 2.megabytes
      generate_variants(attachment)
    end
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "Image attachment #{image_attachment_id} not found: #{e.message}"
  rescue => e
    Rails.logger.error "Failed to process image #{image_attachment_id}: #{e.message}"
  end

  private

  def convert_heic_to_jpeg(attachment)
    old_blob = attachment.blob

    Rails.logger.info "[HEIC_CONVERSION] Converting HEIC image #{attachment.id} to JPEG"

    # Check if ImageMagick supports HEIC
    unless heic_supported?
      Rails.logger.warn "[HEIC_CONVERSION] ImageMagick does not support HEIC format, keeping original"
      return
    end

    # Convert HEIC to JPEG
    new_blob = nil
    old_blob.open do |tempfile|
      converted = ImageProcessing::MiniMagick
        .source(tempfile)
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
          Rails.logger.info "[HEIC_CONVERSION] Old blob already purged: #{old_blob.key}"
        end
      end
    end

    Rails.logger.info "[HEIC_CONVERSION] Successfully converted HEIC to JPEG: #{new_blob.filename}" if new_blob
  rescue ImageProcessing::Error => e
    Rails.logger.error "[HEIC_CONVERSION] HEIC conversion failed: #{e.message}"
    # Keep original HEIC - browser may not display but file is preserved
  rescue => e
    Rails.logger.error "[HEIC_CONVERSION] Unexpected error during HEIC conversion: #{e.message}"
  end

  def generate_variants(attachment)
    # Generate compressed variants in different sizes
    attachment.variant(resize_to_limit: [1200, 1200], quality: 85).processed
    attachment.variant(resize_to_limit: [800, 800], quality: 80).processed
    attachment.variant(resize_to_limit: [300, 300], quality: 75).processed
    Rails.logger.info "[IMAGE_PROCESSING] Generated variants for attachment #{attachment.id}"
  end

  def heic_supported?
    @heic_supported ||= begin
      output = `convert -list format 2>/dev/null`
      output.include?('HEIC') || output.include?('HEIF')
    rescue => e
      Rails.logger.warn "[HEIC_CONVERSION] Could not check ImageMagick format support: #{e.message}"
      false
    end
  end
end 