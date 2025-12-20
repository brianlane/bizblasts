# frozen_string_literal: true

# Background job for processing large image crop operations.
# This job handles image cropping asynchronously to avoid blocking
# web requests for large images.
#
# @example Enqueue a crop job
#   ImageCropJob.perform_later(attachment_id, crop_params, callback_url: "...")
#
# @example Synchronous execution (for small images)
#   ImageCropJob.perform_now(attachment_id, crop_params)
class ImageCropJob < ApplicationJob
  queue_as :image_processing

  # Size threshold in bytes (2MB) - images larger than this are processed in background
  LARGE_IMAGE_THRESHOLD = 2.megabytes

  # Maximum processing time before timeout
  PROCESSING_TIMEOUT = 5.minutes

  retry_on ActiveStorage::FileNotFoundError, wait: 30.seconds, attempts: 3
  retry_on Timeout::Error, wait: 1.minute, attempts: 2

  discard_on ActiveRecord::RecordNotFound

  # Process an image crop operation
  #
  # @param attachment_id [Integer] The ID of the ActiveStorage::Attachment
  # @param crop_params [Hash] The crop parameters (x, y, width, height, rotate, scaleX, scaleY)
  # @param options [Hash] Additional options
  # @option options [String] :callback_url URL to notify when processing completes
  # @option options [Integer] :user_id The user who initiated the crop (for notifications)
  def perform(attachment_id, crop_params, options = {})
    attachment = ActiveStorage::Attachment.find(attachment_id)

    unless attachment.blob.image?
      Rails.logger.warn "[ImageCropJob] Attachment #{attachment_id} is not an image"
      return
    end

    Rails.logger.info "[ImageCropJob] Processing crop for attachment #{attachment_id}"

    # Normalize crop parameters
    normalized_params = normalize_crop_params(crop_params)

    # Process the crop with timeout protection
    result = Timeout.timeout(PROCESSING_TIMEOUT) do
      ImageCropService.crop(attachment, normalized_params)
    end

    if result
      Rails.logger.info "[ImageCropJob] Successfully cropped attachment #{attachment_id}"
      handle_success(attachment, options)
    else
      Rails.logger.error "[ImageCropJob] Crop failed for attachment #{attachment_id}"
      handle_failure(attachment, options, "Crop operation returned false")
    end
  rescue Timeout::Error => e
    Rails.logger.error "[ImageCropJob] Timeout processing attachment #{attachment_id}: #{e.message}"
    handle_failure(attachment, options, "Processing timed out")
    raise # Re-raise for retry
  rescue StandardError => e
    Rails.logger.error "[ImageCropJob] Error cropping attachment #{attachment_id}: #{e.message}"
    handle_failure(attachment, options, e.message)
    raise # Re-raise for retry
  end

  # Determine if an attachment should be processed in the background
  #
  # @param attachment [ActiveStorage::Attachment] The attachment to check
  # @return [Boolean] True if the image should be processed in background
  def self.should_process_async?(attachment)
    return false unless attachment&.blob&.present?
    return false unless attachment.blob.image?

    attachment.blob.byte_size > LARGE_IMAGE_THRESHOLD
  end

  # Enqueue or process immediately based on image size
  #
  # @param attachment [ActiveStorage::Attachment] The attachment to crop
  # @param crop_params [Hash] The crop parameters
  # @param options [Hash] Additional options
  # @return [Boolean] True if enqueued for background, false if processed immediately
  def self.process_crop(attachment, crop_params, options = {})
    if should_process_async?(attachment)
      perform_later(attachment.id, crop_params, options)
      true # Indicates async processing
    else
      # Process synchronously for small images
      ImageCropService.crop(attachment, crop_params)
      false # Indicates sync processing
    end
  end

  private

  def normalize_crop_params(params)
    # Handle both string keys and symbol keys
    {
      x: (params[:x] || params["x"]).to_i,
      y: (params[:y] || params["y"]).to_i,
      width: (params[:width] || params["width"]).to_i,
      height: (params[:height] || params["height"]).to_i,
      rotate: (params[:rotate] || params["rotate"]).to_i,
      scaleX: (params[:scaleX] || params["scaleX"])&.to_f || 1.0,
      scaleY: (params[:scaleY] || params["scaleY"])&.to_f || 1.0
    }
  end

  def handle_success(attachment, options)
    return unless options[:callback_url].present?

    # Notify callback URL if provided
    begin
      uri = URI.parse(options[:callback_url])
      Net::HTTP.post(
        uri,
        { status: "success", attachment_id: attachment.id }.to_json,
        "Content-Type" => "application/json"
      )
    rescue StandardError => e
      Rails.logger.warn "[ImageCropJob] Failed to notify callback: #{e.message}"
    end
  end

  def handle_failure(attachment, options, error_message)
    return unless options[:callback_url].present?

    # Notify callback URL if provided
    begin
      uri = URI.parse(options[:callback_url])
      Net::HTTP.post(
        uri,
        { status: "failed", attachment_id: attachment&.id, error: error_message }.to_json,
        "Content-Type" => "application/json"
      )
    rescue StandardError => e
      Rails.logger.warn "[ImageCropJob] Failed to notify callback: #{e.message}"
    end
  end
end
