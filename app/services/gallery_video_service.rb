# frozen_string_literal: true

# Service class for managing gallery videos
# Handles video uploads, display location settings, and processing
class GalleryVideoService
  class VideoUploadError < StandardError; end
  class VideoNotFoundError < StandardError; end

  ALLOWED_VIDEO_TYPES = %w[video/mp4 video/webm video/quicktime video/x-msvideo].freeze
  MAX_VIDEO_SIZE = 50.megabytes

  # Upload a new gallery video
  # @param business [Business] The business to add the video to
  # @param video_file [ActionDispatch::Http::UploadedFile] The uploaded video file
  # @param attributes [Hash] Additional attributes (video_title, video_display_location, video_autoplay_hero)
  # @return [Business] The updated business
  # @raise [VideoUploadError] if video validation fails
  def self.upload(business, video_file, attributes = {})
    validate_video_file!(video_file)

    # Remove existing video if present
    business.gallery_video.purge if business.gallery_video.attached?

    # Attach new video
    business.gallery_video.attach(video_file)

    # Update video settings
    business.assign_attributes(
      video_title: attributes[:video_title],
      video_display_location: attributes[:video_display_location] || :hero,
      video_autoplay_hero: attributes.fetch(:video_autoplay_hero, true)
    )

    if business.save
      Rails.logger.info "Gallery video uploaded for business #{business.id}"
      business
    else
      Rails.logger.error "Failed to upload gallery video for business #{business.id}: #{business.errors.full_messages.join(', ')}"
      raise VideoUploadError, business.errors.full_messages.join(', ')
    end
  end

  # Update video display settings
  # @param business [Business] The business to update
  # @param location [Symbol, String] Display location: :hero, :gallery, or :both
  # @param autoplay [Boolean] Whether to autoplay in hero section
  # @param title [String, nil] Video title
  # @return [Business] The updated business
  def self.update_display_settings(business, location:, autoplay: true, title: nil)
    raise VideoNotFoundError, "No video attached" unless business.gallery_video.attached?

    valid_locations = %i[hero gallery both]

    # Handle nil or empty location gracefully
    raise ArgumentError, "Display location cannot be nil or empty" if location.blank?

    location_sym = location.to_sym

    unless valid_locations.include?(location_sym)
      raise ArgumentError, "Invalid display location. Must be one of: #{valid_locations.join(', ')}"
    end

    business.update!(
      video_display_location: location_sym,
      video_autoplay_hero: autoplay,
      video_title: title
    )

    Rails.logger.info "Gallery video display settings updated for business #{business.id}: location=#{location_sym}, autoplay=#{autoplay}"
    business
  end

  # Remove the gallery video
  # @param business [Business] The business to remove video from
  # @return [Boolean] Success status
  def self.remove(business)
    return false unless business.gallery_video.attached?

    business.gallery_video.purge

    # Reset video settings to defaults
    # Use update_columns to skip callbacks (especially process_gallery_video)
    # which would otherwise try to process a non-existent video
    business.update_columns(
      video_display_location: Business.video_display_locations[:hero],
      video_title: nil,
      video_autoplay_hero: true,
      video_conversion_status: nil,  # Clear conversion status
      updated_at: Time.current
    )

    Rails.logger.info "Gallery video removed from business #{business.id}"
    true
  rescue StandardError => e
    Rails.logger.error "Failed to remove gallery video from business #{business.id}: #{e.message}"
    false
  end

  # Get video info for display
  # @param business [Business]
  # @return [Hash, nil] Video information or nil if no video
  def self.video_info(business)
    return nil unless business.gallery_video.attached?

    {
      attached: true,
      filename: business.gallery_video.filename.to_s,
      size: business.gallery_video.byte_size,
      size_human: ActiveSupport::NumberHelper.number_to_human_size(business.gallery_video.byte_size),
      content_type: business.gallery_video.content_type,
      url: Rails.application.routes.url_helpers.rails_blob_path(business.gallery_video, only_path: true),
      thumbnail_url: thumbnail_url(business),
      display_location: business.video_display_location,
      autoplay_hero: business.video_autoplay_hero?,
      title: business.video_title,
      displays_in_hero: business.hero_video?,
      displays_in_gallery: business.gallery_video_display?
    }
  end

  # Generate video thumbnail if available
  # @param business [Business]
  # @return [String, nil] Thumbnail URL or nil
  def self.thumbnail_url(business)
    return nil unless business.gallery_video.attached?

    # Thumbnail generation via ActiveStorage variants requires ffmpeg, which isn't available.
    # Return nil so callers can gracefully skip poster images until support is added.
    nil
  end

  private

  # Validate video file before upload
  # @param video_file [ActionDispatch::Http::UploadedFile]
  # @raise [VideoUploadError] if validation fails
  def self.validate_video_file!(video_file)
    if video_file.blank?
      raise VideoUploadError, "No video file provided"
    end

    unless ALLOWED_VIDEO_TYPES.include?(video_file.content_type)
      raise VideoUploadError, "Invalid video format. Allowed formats: MP4, WebM, MOV, AVI"
    end

    if video_file.size > MAX_VIDEO_SIZE
      raise VideoUploadError, "Video file too large. Maximum size: #{ActiveSupport::NumberHelper.number_to_human_size(MAX_VIDEO_SIZE)}"
    end

    true
  end
end
