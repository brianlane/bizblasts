# frozen_string_literal: true

# Service for applying crop transformations to Active Storage attachments
# Processes crop coordinates from client-side cropper (Cropper.js) and applies
# the transformation server-side using ImageMagick via image_processing gem.
#
# Usage:
#   ImageCropService.new(product.images.first, crop_params).call
#   ImageCropService.crop!(attachment, crop_params)
#
# @see https://github.com/fengyuanchen/cropperjs for crop coordinate format
class ImageCropService
  class CropError < StandardError; end
  class InvalidParamsError < CropError; end
  class AttachmentNotFoundError < CropError; end

  # Maximum output dimension after crop (matches client-side limit)
  MAX_DIMENSION = 4096

  # Minimum acceptable crop dimensions
  MIN_CROP_SIZE = 10

  attr_reader :attachment, :crop_params, :errors

  # @param attachment [ActiveStorage::Attached::One, ActiveStorage::Attachment] The image attachment
  # @param crop_params [Hash, String] Crop coordinates - can be Hash or JSON string
  #   - x: [Integer] X offset from top-left
  #   - y: [Integer] Y offset from top-left
  #   - width: [Integer] Width of crop area
  #   - height: [Integer] Height of crop area
  #   - rotate: [Integer, optional] Rotation in degrees (0, 90, 180, 270)
  #   - scaleX: [Float, optional] Horizontal scale (-1 for flip)
  #   - scaleY: [Float, optional] Vertical scale (-1 for flip)
  def initialize(attachment, crop_params)
    @attachment = resolve_attachment(attachment)
    @crop_params = normalize_params(crop_params)
    @errors = []
  end

  # Apply crop transformation
  # @return [Boolean] Success status
  def call
    return false unless valid?

    process_crop
    true
  rescue StandardError => e
    @errors << e.message
    Rails.logger.error "[IMAGE_CROP] Failed to crop image: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    false
  end

  # Apply crop transformation, raising on failure
  # @return [ActiveStorage::Attachment] The updated attachment
  # @raise [AttachmentNotFoundError] when attachment is missing
  # @raise [InvalidParamsError] when crop params are invalid
  # @raise [CropError] on processing failure
  def call!
    validate! # Raises AttachmentNotFoundError or InvalidParamsError if invalid

    process_crop
    @attachment
  rescue AttachmentNotFoundError, InvalidParamsError
    raise # Re-raise specific errors
  rescue StandardError => e
    raise CropError, "Failed to crop image: #{e.message}"
  end

  # Class method for simple usage
  # @param attachment [ActiveStorage::Attached::One, ActiveStorage::Attachment]
  # @param crop_params [Hash, String]
  # @return [Boolean]
  def self.crop(attachment, crop_params)
    new(attachment, crop_params).call
  end

  # Class method that raises on failure
  # @param attachment [ActiveStorage::Attached::One, ActiveStorage::Attachment]
  # @param crop_params [Hash, String]
  # @return [ActiveStorage::Attachment]
  # @raise [CropError]
  def self.crop!(attachment, crop_params)
    new(attachment, crop_params).call!
  end

  # Crop an image attachment on a model record
  # @param record [ActiveRecord::Base] The model record with the attachment
  # @param attachment_name [Symbol] Name of the attachment (e.g., :image, :logo)
  # @param crop_params [Hash, String] Crop coordinates
  # @return [Hash] Result hash with :success and :error keys
  def self.crop_attached_image(record, attachment_name, crop_params)
    attachment = record.send(attachment_name)

    unless attachment.attached?
      return { success: false, error: "No image attached" }
    end

    service = new(attachment, crop_params)
    if service.call
      record.reload # Reload to get updated attachment
      { success: true }
    else
      { success: false, error: service.errors.join(", ") }
    end
  rescue StandardError => e
    Rails.logger.error "[IMAGE_CROP] crop_attached_image failed: #{e.message}"
    { success: false, error: e.message }
  end

  private

  # Resolve attachment from various input types
  def resolve_attachment(attachment)
    case attachment
    when ActiveStorage::Attachment
      attachment
    when ActiveStorage::Attached::One
      attachment.attachment
    else
      attachment
    end
  end

  # Normalize crop parameters from various formats
  def normalize_params(params)
    # Handle JSON string input
    params = JSON.parse(params) if params.is_a?(String)

    # Convert to hash with indifferent access
    params = params.to_h.with_indifferent_access if params.respond_to?(:to_h)

    return {} unless params.is_a?(Hash)

    {
      x: params[:x].to_i,
      y: params[:y].to_i,
      width: params[:width].to_i,
      height: params[:height].to_i,
      rotate: params[:rotate].to_i,
      scaleX: params[:scaleX]&.to_f || 1.0,
      scaleY: params[:scaleY]&.to_f || 1.0
    }
  rescue JSON::ParserError => e
    Rails.logger.warn "[IMAGE_CROP] Invalid JSON crop params: #{e.message}"
    {}
  end

  # Validate inputs before processing
  # @raise [AttachmentNotFoundError] when attachment is missing (for call!)
  def valid?
    @errors = []

    # Check if we have an attachment
    unless attachment_present?
      @errors << "No image attached"
      return false
    end

    unless @attachment.blob&.image?
      @errors << "Attachment is not an image"
      return false
    end

    if @crop_params[:width].to_i < MIN_CROP_SIZE
      @errors << "Crop width must be at least #{MIN_CROP_SIZE}px"
    end

    if @crop_params[:height].to_i < MIN_CROP_SIZE
      @errors << "Crop height must be at least #{MIN_CROP_SIZE}px"
    end

    if @crop_params[:x].to_i < 0 || @crop_params[:y].to_i < 0
      @errors << "Crop coordinates cannot be negative"
    end

    @errors.empty?
  end

  # Validate and raise AttachmentNotFoundError if missing
  # Used by call! for explicit error handling
  def validate!
    unless attachment_present?
      raise AttachmentNotFoundError, "No image attached"
    end

    unless @attachment.blob&.image?
      raise InvalidParamsError, "Attachment is not an image"
    end

    unless valid?
      raise InvalidParamsError, @errors.join(", ")
    end

    true
  end

  # Check if attachment is present (handles both Attached and Attachment)
  def attachment_present?
    return false if @attachment.nil?

    case @attachment
    when ActiveStorage::Attachment
      @attachment.blob.present?
    when ActiveStorage::Attached::One
      @attachment.attached?
    else
      @attachment.respond_to?(:blob) && @attachment.blob.present?
    end
  end

  # Apply the crop transformation
  def process_crop
    @attachment.blob.open do |tempfile|
      pipeline = ImageProcessing::MiniMagick.source(tempfile)

      # Apply rotation first if specified
      if @crop_params[:rotate] != 0
        pipeline = pipeline.rotate(@crop_params[:rotate])
      end

      # Apply flip transformations
      if @crop_params[:scaleX] == -1
        pipeline = pipeline.flop # Horizontal flip
      end

      if @crop_params[:scaleY] == -1
        pipeline = pipeline.flip # Vertical flip
      end

      # Apply crop - using ImageMagick crop format
      # For ImageMagick, crop is WIDTHxHEIGHT+X+Y
      crop_geometry = "#{@crop_params[:width]}x#{@crop_params[:height]}+#{@crop_params[:x]}+#{@crop_params[:y]}"
      pipeline = pipeline.custom { |cmd| cmd.crop(crop_geometry) }

      # Remove potential offset from crop operation
      pipeline = pipeline.custom { |cmd| cmd.repage.+ }

      # Resize if resulting image is larger than max dimension
      pipeline = pipeline.resize_to_limit(MAX_DIMENSION, MAX_DIMENSION)

      # Apply quality settings for reasonable file size
      pipeline = pipeline.saver(quality: 90)

      # Process and get result file
      cropped_file = pipeline.call

      # Create new blob with cropped content
      new_blob = ActiveStorage::Blob.create_and_upload!(
        io: File.open(cropped_file),
        filename: @attachment.blob.filename,
        content_type: @attachment.blob.content_type
      )

      # Update attachment to point to new blob
      old_blob = @attachment.blob
      @attachment.update!(blob: new_blob)

      # Schedule old blob for deletion
      old_blob.purge_later

      Rails.logger.info "[IMAGE_CROP] Successfully cropped image: #{@attachment.blob.filename}"
    end
  end
end
