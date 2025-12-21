# frozen_string_literal: true

module JobAttachmentsHelper
  # Returns CSS classes for attachment type badges
  def attachment_type_badge_class(type)
    case type.to_s
    when 'before_photo'
      'bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200'
    when 'after_photo'
      'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200'
    when 'instruction'
      'bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200'
    when 'reference_file'
      'bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-200'
    else
      'bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-200'
    end
  end

  # Returns CSS classes for attachment visibility badges
  def attachment_visibility_badge_class(visibility)
    case visibility.to_s
    when 'customer_visible'
      'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200'
    when 'internal'
      'bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-200'
    else
      'bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-200'
    end
  end
end

