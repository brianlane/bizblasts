class ProcessImageJob < ApplicationJob
  # Use dedicated image_processing queue with single thread to prevent memory spikes
  # Image processing is memory-intensive: a 4000x3000 image = ~48MB uncompressed
  queue_as :image_processing

  # Maximum file size to process (10MB) - larger files risk OOM
  MAX_PROCESSABLE_SIZE = 10.megabytes

  def perform(image_attachment_id)
    attachment = ActiveStorage::Attachment.find(image_attachment_id)
    blob = attachment.blob

    # Skip processing for very large files to prevent OOM
    if blob.byte_size > MAX_PROCESSABLE_SIZE
      Rails.logger.warn "[IMAGE_PROCESSING] Skipping variant generation for large file #{blob.filename} (#{blob.byte_size} bytes > #{MAX_PROCESSABLE_SIZE})"
      return
    end

    # Convert HEIC to JPEG if needed - MUST happen before variant generation
    if FileUploadSecurity.heic_format?(blob.content_type)
      convert_heic_to_jpeg(attachment)
      # Force garbage collection after HEIC conversion to free memory
      force_gc
      # Reload attachment after conversion and verify it succeeded
      attachment.reload
      begin
        blob = attachment.blob
      rescue ActiveRecord::RecordNotFound => e
        Rails.logger.error "[IMAGE_PROCESSING] Attachment or blob not found after HEIC conversion: #{e.message}"
        return
      end
      return unless blob
    end

    # Always generate variants for images (HEIC can be small in bytes yet high-res)
    if blob.image?
      generate_variants(attachment)
    end
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "Image attachment #{image_attachment_id} not found: #{e.message}"
  rescue => e
    Rails.logger.error "Failed to process image #{image_attachment_id}: #{e.message}"
  ensure
    # Always force GC at end of job to release image memory promptly
    force_gc
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
    # Generate compressed variants one at a time with GC between each
    # This prevents memory accumulation from multiple concurrent variant generations
    variants = [
      { resize_to_limit: [1200, 1200], quality: 85 },
      { resize_to_limit: [800, 800], quality: 80 },
      { resize_to_limit: [300, 300], quality: 75 }
    ]

    variants.each_with_index do |variant_options, index|
      begin
        attachment.variant(variant_options).processed
        Rails.logger.debug "[IMAGE_PROCESSING] Generated variant #{index + 1}/#{variants.size} for attachment #{attachment.id}"
      rescue => e
        Rails.logger.error "[IMAGE_PROCESSING] Failed to generate variant #{index + 1} for attachment #{attachment.id}: #{e.message}"
      ensure
        # Force GC between variants to release image memory
        force_gc
      end
    end

    Rails.logger.info "[IMAGE_PROCESSING] Generated #{variants.size} variants for attachment #{attachment.id}"
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

  # Force garbage collection to release image processing memory
  # This is critical for memory-constrained environments
  def force_gc
    GC.start(full_mark: true, immediate_sweep: true)
  end
end