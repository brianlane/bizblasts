# frozen_string_literal: true

module JobFormsHelper
  # Returns CSS classes for job form submission status badges
  def submission_status_badge_class(status)
    case status.to_s
    when 'draft'
      'bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-200'
    when 'submitted'
      'bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200'
    when 'approved'
      'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200'
    when 'requires_revision'
      'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200'
    else
      'bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-200'
    end
  end

  # Returns CSS classes for timing section borders
  def timing_border_class(timing)
    case timing.to_s
    when 'before_service'
      'border-yellow-400'
    when 'during_service'
      'border-blue-400'
    when 'after_service'
      'border-green-400'
    else
      'border-gray-400'
    end
  end

  # Returns CSS classes for timing section backgrounds
  def timing_background_class(timing)
    case timing.to_s
    when 'before_service'
      'bg-yellow-50 dark:bg-yellow-900'
    when 'during_service'
      'bg-blue-50 dark:bg-blue-900'
    when 'after_service'
      'bg-green-50 dark:bg-green-900'
    else
      'bg-gray-50 dark:bg-gray-900'
    end
  end

  # Human-readable timing display
  def timing_display(timing)
    case timing.to_s
    when 'before_service' then 'Before Service'
    when 'during_service' then 'During Service'
    when 'after_service' then 'After Service'
    else timing.to_s.humanize
    end
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

