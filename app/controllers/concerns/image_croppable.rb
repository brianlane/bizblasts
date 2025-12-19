# frozen_string_literal: true

# Concern for controllers that handle image cropping functionality.
# Provides shared methods for parsing crop data, processing crops,
# and handling multi-image crop operations.
#
# @example Including in a controller
#   class ProductsController < ApplicationController
#     include ImageCroppable
#   end
#
# @example Processing crop data in an action
#   def crop_image
#     crop_params = parse_crop_params(params[:crop_data])
#     result = ImageCropService.crop(attachment, crop_params)
#   end
module ImageCroppable
  extend ActiveSupport::Concern

  # Allowed keys for crop parameters (whitelist for security)
  ALLOWED_CROP_KEYS = %w[x y width height rotate scaleX scaleY].freeze

  # Valid image content types for cropping
  VALID_IMAGE_TYPES = %w[
    image/png
    image/jpeg
    image/jpg
    image/gif
    image/webp
    image/heic
    image/heif
  ].freeze

  # Parse and sanitize crop parameters from various input formats.
  # This replaces the insecure `to_unsafe_h` pattern with proper parameter filtering.
  #
  # @param crop_data [String, Hash, ActionController::Parameters] Raw crop data
  # @return [Hash] Sanitized crop parameters with only allowed keys
  def parse_crop_params(crop_data)
    return {} if crop_data.blank?

    # Parse JSON string if needed
    parsed = if crop_data.is_a?(String)
               begin
                 JSON.parse(crop_data)
               rescue JSON::ParserError => e
                 Rails.logger.warn "[IMAGE_CROP] Invalid JSON crop data: #{e.message}"
                 return {}
               end
             elsif crop_data.is_a?(ActionController::Parameters)
               # Safely convert ActionController::Parameters to hash with permitted keys
               crop_data.permit(*ALLOWED_CROP_KEYS).to_h
             elsif crop_data.respond_to?(:to_h)
               crop_data.to_h
             else
               crop_data
             end

    # Whitelist only allowed keys and convert to proper types
    sanitize_crop_params(parsed)
  end

  # Process crop data for multiple images (used in form submissions).
  # Handles the images_crop_data hash keyed by attachment ID.
  #
  # @param record [ActiveRecord::Base] The record with image attachments
  # @param attachment_name [Symbol] Name of the images attachment (e.g., :images)
  # @param crop_data_hash [Hash] Hash of attachment_id => crop_data
  # @return [Hash] Results hash with success/failure per attachment
  def process_multi_image_crops(record, attachment_name, crop_data_hash)
    return {} if crop_data_hash.blank?

    results = {}

    crop_data_hash.each do |attachment_id, crop_json|
      next if crop_json.blank?

      begin
        crop_data = parse_crop_params(crop_json)
        next if crop_data.blank?

        # Find the attachment by ID
        attachment = record.send(attachment_name).attachments.find_by(id: attachment_id)
        unless attachment
          Rails.logger.warn "[IMAGE_CROP] Attachment #{attachment_id} not found for #{record.class.name} #{record.id}"
          results[attachment_id] = { success: false, error: "Attachment not found" }
          next
        end

        # Apply crop using ImageCropService
        result = ImageCropService.crop(attachment, crop_data)
        if result
          Rails.logger.info "[IMAGE_CROP] Successfully cropped attachment #{attachment_id} for #{record.class.name} #{record.id}"
          results[attachment_id] = { success: true }
        else
          Rails.logger.warn "[IMAGE_CROP] Crop operation returned false for attachment #{attachment_id}"
          results[attachment_id] = { success: false, error: "Crop operation failed" }
        end
      rescue StandardError => e
        Rails.logger.error "[IMAGE_CROP] Error cropping attachment #{attachment_id}: #{e.message}"
        results[attachment_id] = { success: false, error: e.message }
      end
    end

    results
  end

  # Process a single attachment crop (for logo, photo, etc.)
  #
  # @param record [ActiveRecord::Base] The record with the attachment
  # @param attachment_name [Symbol] Name of the attachment (e.g., :logo, :photo)
  # @param crop_data [String, Hash] Crop parameters
  # @return [Boolean] Success status
  def process_single_image_crop(record, attachment_name, crop_data)
    attachment = record.send(attachment_name)
    return false unless attachment.attached? && crop_data.present?

    begin
      crop_params = parse_crop_params(crop_data)
      return false if crop_params.blank?

      result = ImageCropService.crop(attachment, crop_params)
      unless result
        Rails.logger.warn "[IMAGE_CROP] #{attachment_name} crop failed for #{record.class.name} #{record.id}"
      end
      result
    rescue StandardError => e
      Rails.logger.error "[IMAGE_CROP] #{attachment_name} crop error for #{record.class.name} #{record.id}: #{e.message}"
      false
    end
  end

  # Validate that an attachment is a valid image type for cropping.
  #
  # @param attachment [ActiveStorage::Attachment] The attachment to validate
  # @return [Boolean] True if valid image type
  def valid_image_for_crop?(attachment)
    return false unless attachment&.blob&.present?

    VALID_IMAGE_TYPES.include?(attachment.blob.content_type)
  end

  # Render a crop error response in the appropriate format.
  #
  # @param error_message [String] The error message to display
  # @param redirect_path [String] Path to redirect to for HTML format
  def render_crop_error(error_message, redirect_path)
    respond_to do |format|
      format.html { redirect_to redirect_path, alert: error_message }
      format.json { render json: { success: false, error: error_message }, status: :unprocessable_entity }
    end
  end

  private

  # Sanitize crop parameters to only include allowed keys with proper types.
  #
  # @param params [Hash] Raw parameters
  # @return [Hash] Sanitized parameters
  def sanitize_crop_params(params)
    return {} unless params.is_a?(Hash)

    {
      x: params["x"].to_i,
      y: params["y"].to_i,
      width: params["width"].to_i,
      height: params["height"].to_i,
      rotate: params["rotate"].to_i,
      scaleX: params["scaleX"]&.to_f || 1.0,
      scaleY: params["scaleY"]&.to_f || 1.0
    }.tap do |result|
      # Also check symbol keys
      result[:x] = params[:x].to_i if params.key?(:x)
      result[:y] = params[:y].to_i if params.key?(:y)
      result[:width] = params[:width].to_i if params.key?(:width)
      result[:height] = params[:height].to_i if params.key?(:height)
      result[:rotate] = params[:rotate].to_i if params.key?(:rotate)
      result[:scaleX] = params[:scaleX]&.to_f || 1.0 if params.key?(:scaleX)
      result[:scaleY] = params[:scaleY]&.to_f || 1.0 if params.key?(:scaleY)
    end
  end
end
