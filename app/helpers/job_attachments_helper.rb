# frozen_string_literal: true

module JobAttachmentsHelper
  # CSS class constants for consistency
  ATTACHMENT_TYPE_BADGE_CLASSES = {
    'before_photo' => 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200',
    'after_photo' => 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200',
    'instruction' => 'bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200',
    'reference_file' => 'bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-200'
  }.freeze

  VISIBILITY_BADGE_CLASSES = {
    'customer_visible' => 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200',
    'internal' => 'bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-200'
  }.freeze

  DEFAULT_BADGE_CLASS = 'bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-200'

  # Returns CSS classes for attachment type badges
  def attachment_type_badge_class(type)
    ATTACHMENT_TYPE_BADGE_CLASSES[type.to_s] || DEFAULT_BADGE_CLASS
  end

  # Returns CSS classes for attachment visibility badges
  def attachment_visibility_badge_class(visibility)
    VISIBILITY_BADGE_CLASSES[visibility.to_s] || DEFAULT_BADGE_CLASS
  end
end

