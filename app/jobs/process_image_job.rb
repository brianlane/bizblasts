class ProcessImageJob < ApplicationJob
  queue_as :default

  def perform(image_attachment_id)
    attachment = ActiveStorage::Attachment.find(image_attachment_id)
    blob = attachment.blob

    # Only process if it's an image and larger than 2MB
    if blob.image? && blob.byte_size > 2.megabytes
      # Generate compressed variants in different sizes
      attachment.variant(resize_to_limit: [1200, 1200], quality: 85).processed
      attachment.variant(resize_to_limit: [800, 800], quality: 80).processed
      attachment.variant(resize_to_limit: [300, 300], quality: 75).processed
    end
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "Image attachment #{image_attachment_id} not found: #{e.message}"
  rescue => e
    Rails.logger.error "Failed to process image #{image_attachment_id}: #{e.message}"
  end
end 