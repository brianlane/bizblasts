class ProcessGalleryVideoJob < ApplicationJob
  queue_as :default

  # Maximum video duration in seconds (5 minutes)
  MAX_DURATION = 300

  # Maximum video file size in bytes (50 MB)
  MAX_FILE_SIZE = 50.megabytes

  # @param business_id [Integer] The business ID
  # @param expected_blob_id [Integer, nil] Optional blob ID to verify video hasn't changed
  def perform(business_id, expected_blob_id = nil)
    business = Business.find(business_id)

    return unless business.gallery_video.attached?

    blob = business.gallery_video.blob

    # If expected_blob_id is provided, verify video hasn't changed (race condition check)
    if expected_blob_id.present? && blob.id != expected_blob_id
      Rails.logger.info "[GALLERY_VIDEO_PROCESSING] Video changed since job was enqueued (expected blob #{expected_blob_id}, found #{blob.id}). Skipping."
      return
    end

    # Store the blob_id for conversion race condition check
    @original_blob_id = blob.id

    # Validate video file
    validate_video!(blob)

    # Log video info for debugging
    log_video_info(business, blob)

    # Convert to MP4 if needed for web compatibility
    convert_to_mp4_if_needed(business)

    # Generate video thumbnail if needed
    # generate_thumbnail(business) if thumbnail_generation_supported?

    Rails.logger.info "[GALLERY_VIDEO_PROCESSING] Successfully processed video for business #{business_id}"
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "Business #{business_id} not found: #{e.message}"
  rescue VideoProcessingError => e
    Rails.logger.error "Video validation failed for business #{business_id}: #{e.message}"
    handle_invalid_video(business_id, e.message)
  rescue => e
    Rails.logger.error "Failed to process gallery video for business #{business_id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end

  private

  def validate_video!(blob)
    # Check file size
    if blob.byte_size > MAX_FILE_SIZE
      raise VideoProcessingError, "Video file size exceeds maximum allowed size of #{MAX_FILE_SIZE / 1.megabyte}MB"
    end

    # Check content type
    valid_types = ['video/mp4', 'video/webm', 'video/quicktime', 'video/x-msvideo']
    unless valid_types.include?(blob.content_type)
      raise VideoProcessingError, "Invalid video format. Supported formats: MP4, WebM, MOV, AVI"
    end

    Rails.logger.info "[GALLERY_VIDEO_VALIDATION] Video validation passed for blob #{blob.id}"
  end

  def log_video_info(business, blob)
    Rails.logger.info <<~LOG
      [GALLERY_VIDEO_INFO] Processing video for business #{business.id}:
        - Filename: #{blob.filename}
        - Content Type: #{blob.content_type}
        - Size: #{(blob.byte_size / 1.megabyte.to_f).round(2)}MB
        - Key: #{blob.key}
    LOG
  end

  def convert_to_mp4_if_needed(business)
    blob = business.gallery_video.blob

    if VideoConversionService.needs_conversion?(blob)
      Rails.logger.info "[GALLERY_VIDEO_PROCESSING] Video needs conversion to MP4 for web compatibility"

      # Pass original blob ID to prevent race condition if video is deleted during conversion
      if VideoConversionService.convert!(business, original_blob_id: @original_blob_id)
        Rails.logger.info "[GALLERY_VIDEO_PROCESSING] Video converted to MP4 successfully"
      else
        Rails.logger.warn "[GALLERY_VIDEO_PROCESSING] Video conversion skipped (ffmpeg not available, conversion failed, or video was deleted)"
      end
    else
      Rails.logger.info "[GALLERY_VIDEO_PROCESSING] Video is already in web-compatible format"
    end
  end

  def thumbnail_generation_supported?
    # Check if ffmpeg is available for thumbnail generation
    @ffmpeg_available ||= begin
      `which ffmpeg 2>/dev/null`.present?
    rescue => e
      Rails.logger.warn "[GALLERY_VIDEO_PROCESSING] Could not check for ffmpeg: #{e.message}"
      false
    end
  end

  def generate_thumbnail(business)
    # Future enhancement: Generate video thumbnail using ffmpeg
    # This would create a preview image for the video player
    Rails.logger.info "[GALLERY_VIDEO_PROCESSING] Thumbnail generation not yet implemented for business #{business.id}"
  end

  def handle_invalid_video(business_id, error_message)
    # Future enhancement: Notify business owner of invalid video
    # Could send an email or create a notification
    Rails.logger.error "[GALLERY_VIDEO_PROCESSING] Invalid video for business #{business_id}: #{error_message}"

    begin
      business = Business.find(business_id)
      # Remove the invalid video attachment
      business.gallery_video.purge_later if business.gallery_video.attached?
      Rails.logger.info "[GALLERY_VIDEO_PROCESSING] Removed invalid video for business #{business_id}"
    rescue => e
      Rails.logger.error "[GALLERY_VIDEO_PROCESSING] Failed to remove invalid video: #{e.message}"
    end
  end

  class VideoProcessingError < StandardError; end
end
