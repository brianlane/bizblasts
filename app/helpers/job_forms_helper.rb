# frozen_string_literal: true

module JobFormsHelper
  # CSS class constants for consistency
  STATUS_BADGE_CLASSES = {
    'draft' => 'bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-200',
    'submitted' => 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200',
    'approved' => 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200',
    'requires_revision' => 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200'
  }.freeze

  TIMING_BORDER_CLASSES = {
    'before_service' => 'border-yellow-400',
    'during_service' => 'border-blue-400',
    'after_service' => 'border-green-400'
  }.freeze

  TIMING_BACKGROUND_CLASSES = {
    'before_service' => 'bg-yellow-50 dark:bg-yellow-900',
    'during_service' => 'bg-blue-50 dark:bg-blue-900',
    'after_service' => 'bg-green-50 dark:bg-green-900'
  }.freeze

  TIMING_LABELS = {
    'before_service' => 'Before Service',
    'during_service' => 'During Service',
    'after_service' => 'After Service'
  }.freeze

  # Returns CSS classes for job form submission status badges
  def submission_status_badge_class(status)
    STATUS_BADGE_CLASSES[status.to_s] || STATUS_BADGE_CLASSES['draft']
  end

  # Returns CSS classes for timing section borders
  def timing_border_class(timing)
    TIMING_BORDER_CLASSES[timing.to_s] || 'border-gray-400'
  end

  # Returns CSS classes for timing section backgrounds
  def timing_background_class(timing)
    TIMING_BACKGROUND_CLASSES[timing.to_s] || 'bg-gray-50 dark:bg-gray-900'
  end

  # Human-readable timing display
  def timing_display(timing)
    TIMING_LABELS[timing.to_s] || timing.to_s.humanize
  end

  # Resolves a photo field value to actual image URL(s) from Active Storage
  # Returns nil if no photo found, a URL string, or array of URL strings
  def resolve_photo_value(field_value, submission, field_id = nil)
    return nil if field_value.blank?

    # If it's a hash with type 'photo', look up from Active Storage
    if field_value.is_a?(Hash) && field_value['type'] == 'photo'
      # Prefer blob_signed_id for unique lookup (handles duplicate filenames)
      if field_value['blob_signed_id'].present? && submission.photos.attached?
        blob = ActiveStorage::Blob.find_signed(field_value['blob_signed_id'])
        if blob
          attachment = submission.photos.find { |p| p.blob_id == blob.id }
          return rails_blob_url(attachment, only_path: true) if attachment
        end
      end
      
      # Fallback to filename lookup for legacy data
      filename = field_value['filename']
      if filename.present? && submission.photos.attached?
        photo = submission.photos.find { |p| p.filename.to_s == filename }
        return rails_blob_url(photo, only_path: true) if photo
      end
      return nil
    end

    # If it's already a URL string, return as-is (legacy data)
    if field_value.is_a?(String) && field_value.start_with?('http', '/')
      return field_value
    end

    # If it's an array, resolve each element
    if field_value.is_a?(Array)
      urls = field_value.map { |v| resolve_photo_value(v, submission, field_id) }.compact
      return urls.presence
    end

    nil
  end

  # Returns icon class/path for field types
  def field_type_icon(field_type)
    case field_type.to_s
    when 'checkbox'
      'M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z'
    when 'text'
      'M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z'
    when 'textarea'
      'M4 6h16M4 12h16M4 18h7'
    when 'photo'
      'M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z'
    when 'select'
      'M8 9l4-4 4 4m0 6l-4 4-4-4'
    when 'number'
      'M7 20l4-16m2 16l4-16M6 9h14M4 15h14'
    when 'date'
      'M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z'
    when 'time'
      'M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z'
    when 'signature'
      'M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z'
    else
      'M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z'
    end
  end
end

