# frozen_string_literal: true

require 'open3'

# Service class for converting video files to web-optimized MP4 format
# Uses ffmpeg for conversion when available
class VideoConversionService
  class ConversionError < StandardError; end
  class FfmpegNotAvailableError < ConversionError; end
  class VideoDeletedError < ConversionError; end

  # Conversion status values
  STATUS_PENDING = 'pending'
  STATUS_CONVERTING = 'converting'
  STATUS_COMPLETED = 'completed'
  STATUS_FAILED = 'failed'
  STATUS_FAILED_NO_FFMPEG = 'failed_no_ffmpeg'

  # Video formats that need conversion to MP4
  # HEVC/H.265 in .mov containers will be converted to H.264 for better browser support
  CONVERTIBLE_TYPES = %w[video/quicktime video/x-msvideo video/x-ms-wmv].freeze

  # Target format settings
  TARGET_CONTENT_TYPE = 'video/mp4'
  TARGET_EXTENSION = '.mp4'

  class << self
    # Check if a video needs conversion
    # @param blob [ActiveStorage::Blob]
    # @return [Boolean]
    def needs_conversion?(blob)
      return false if blob.nil?

      CONVERTIBLE_TYPES.include?(blob.content_type)
    end

    # Check if ffmpeg is available on the system
    # @return [Boolean]
    def ffmpeg_available?
      @ffmpeg_available ||= begin
        system('which ffmpeg > /dev/null 2>&1')
      rescue StandardError
        false
      end
    end

    # Convert a video to web-optimized MP4
    # @param business [Business] The business with the video attachment
    # @param original_blob_id [Integer, nil] The blob ID when conversion was initiated (for race condition check)
    # @return [Boolean] Success status
    def convert!(business, original_blob_id: nil)
      return false unless business.gallery_video.attached?

      blob = business.gallery_video.blob

      # If original_blob_id was provided, verify the video hasn't been deleted/replaced
      if original_blob_id.present? && blob.id != original_blob_id
        Rails.logger.info "[VIDEO_CONVERSION] Video was replaced or deleted since conversion started (expected blob #{original_blob_id}, found #{blob.id}). Skipping."
        return false
      end

      unless needs_conversion?(blob)
        Rails.logger.info "[VIDEO_CONVERSION] Video #{blob.filename} is already in a web-compatible format"
        # Clear any stale conversion status
        business.update_columns(video_conversion_status: nil) if business.video_conversion_status.present?
        return true
      end

      unless ffmpeg_available?
        Rails.logger.warn "[VIDEO_CONVERSION] ffmpeg not available, skipping conversion for #{blob.filename}"
        # Mark as failed so UI shows appropriate message
        business.update_columns(video_conversion_status: STATUS_FAILED_NO_FFMPEG)
        return false
      end

      # Mark conversion as in progress
      business.update_columns(video_conversion_status: STATUS_CONVERTING)

      perform_conversion(business, blob)
    end

    private

    def perform_conversion(business, blob)
      original_blob_id = blob.id
      Rails.logger.info "[VIDEO_CONVERSION] Starting conversion of #{blob.filename} (#{blob.content_type}) to MP4 (blob_id: #{original_blob_id})"

      original_filename = blob.filename.to_s
      base_name = File.basename(original_filename, '.*')
      new_filename = "#{base_name}#{TARGET_EXTENSION}"

      Dir.mktmpdir('video_conversion') do |tmpdir|
        input_path = File.join(tmpdir, original_filename)
        output_path = File.join(tmpdir, new_filename)

        # Download the original video
        download_blob(blob, input_path)

        # Convert to MP4
        convert_video(input_path, output_path)

        # Verify the output file exists and has content
        unless File.exist?(output_path) && File.size(output_path) > 0
          raise ConversionError, "Conversion failed: output file is empty or missing"
        end

        # Check if video was deleted/replaced during conversion (before replacing)
        business.reload
        unless business.gallery_video.attached?
          Rails.logger.info "[VIDEO_CONVERSION] Video was deleted during conversion. Skipping replacement."
          business.update_columns(video_conversion_status: nil)
          return false
        end

        current_blob_id = business.gallery_video.blob.id
        if current_blob_id != original_blob_id
          Rails.logger.info "[VIDEO_CONVERSION] Video was replaced during conversion (original: #{original_blob_id}, current: #{current_blob_id}). Skipping."
          return false
        end

        # Replace the original attachment with the converted file
        # Mark as completed BEFORE attaching to prevent redundant job trigger
        business.update_columns(video_conversion_status: STATUS_COMPLETED)

        replace_attachment(business, output_path, new_filename)

        Rails.logger.info "[VIDEO_CONVERSION] Successfully converted #{original_filename} to #{new_filename}"
      end

      true
    rescue StandardError => e
      Rails.logger.error "[VIDEO_CONVERSION] Failed to convert video: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      # Mark as failed
      business.update_columns(video_conversion_status: STATUS_FAILED) rescue nil
      false
    end

    def download_blob(blob, destination)
      File.open(destination, 'wb') do |file|
        blob.download { |chunk| file.write(chunk) }
      end
    end

    def convert_video(input_path, output_path)
      # Build command arguments array for safe execution (no shell injection)
      args = [
        'ffmpeg',
        '-i', input_path,
        '-c:v', 'libx264',
        '-preset', 'medium',
        '-crf', '23',
        '-c:a', 'aac',
        '-b:a', '128k',
        '-movflags', '+faststart',
        '-pix_fmt', 'yuv420p',
        '-y', output_path
      ]

      Rails.logger.info "[VIDEO_CONVERSION] Running: ffmpeg -i [input] ... -y [output]"

      # Use Open3 for safe command execution without shell interpolation
      stdout_and_stderr, status = Open3.capture2e(*args)

      unless status.success?
        raise ConversionError, "ffmpeg exited with status #{status.exitstatus}: #{stdout_and_stderr.to_s.last(500)}"
      end

      Rails.logger.info "[VIDEO_CONVERSION] ffmpeg completed successfully"
    end

    def replace_attachment(business, file_path, filename)
      File.open(file_path, 'rb') do |file|
        # Purge the old attachment
        business.gallery_video.purge

        # Attach the converted file
        business.gallery_video.attach(
          io: file,
          filename: filename,
          content_type: TARGET_CONTENT_TYPE
        )
      end
    end
  end
end

