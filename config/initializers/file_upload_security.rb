# frozen_string_literal: true

# SECURITY FIX: Centralized file upload security configuration

module FileUploadSecurity
  # Allowed MIME types for image uploads
  ALLOWED_IMAGE_TYPES = %w[
    image/jpeg
    image/png
    image/gif
    image/webp
    image/heic
    image/heif
    image/heic-sequence
    image/heif-sequence
  ].freeze

  # Maximum file size for images (15MB)
  MAX_IMAGE_SIZE = 15.megabytes

  # File type validation helper
  def self.valid_image_type?(content_type)
    ALLOWED_IMAGE_TYPES.include?(content_type)
  end

  # File size validation helper
  def self.valid_image_size?(byte_size)
    byte_size < MAX_IMAGE_SIZE
  end

  # Virus scanning placeholder (implement with ClamAV or similar)
  def self.scan_for_virus(file_path)
    # TODO: Implement virus scanning
    # For now, return true (safe)
    # In production, integrate with ClamAV:
    # system("clamscan --quiet --infected #{file_path}")
    true
  end

  # Centralized validation method for models
  def self.image_validation_options
    {
      content_type: {
        in: ALLOWED_IMAGE_TYPES,
        message: 'must be a valid image format (PNG, JPEG, GIF, WebP, HEIC, HEIF)'
      },
      size: {
        less_than: MAX_IMAGE_SIZE,
        message: 'must be less than 15MB'
      }
    }
  end

  # Check if image format is HEIC/HEIF
  def self.heic_format?(content_type)
    %w[image/heic image/heif image/heic-sequence image/heif-sequence].include?(content_type)
  end

  # Image metadata stripping for privacy
  def self.strip_metadata(image_blob)
    return unless image_blob.image?

    # Strip EXIF data including GPS coordinates for privacy (especially for HEIC)                                                                              
    if %w[image/heic image/heif image/heic-sequence image/heif-sequence image/jpeg].include?(image_blob.content_type)
      # TODO: Implement EXIF stripping with mini_magick
      # MiniMagick::Image.open(image_blob.download).strip
    end

    Rails.logger.info "[FILE_SECURITY] Image uploaded: #{image_blob.filename} (#{image_blob.byte_size} bytes)"
  end
end

# Extend ActiveStorage validations with centralized security
# Use the correct ActiveSupport hook for ActiveStorage
ActiveSupport.on_load(:active_storage_blob) do
  # Add logging for all file uploads
  after_create :log_upload_security_event

  private

  def log_upload_security_event
    Rails.logger.info "[FILE_UPLOAD] File uploaded: #{filename} (#{content_type}, #{byte_size} bytes)"
    
    # Log potentially suspicious uploads
    if byte_size > 10.megabytes
      Rails.logger.warn "[FILE_SECURITY] Large file uploaded: #{filename} (#{byte_size} bytes)"
    end
    
    unless FileUploadSecurity.valid_image_type?(content_type)
      Rails.logger.warn "[FILE_SECURITY] Non-standard content type: #{content_type} for #{filename}"
    end
  end
end 