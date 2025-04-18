# frozen_string_literal: true

# Global view helpers available throughout the application
# Contains commonly used formatting and presentation logic
module ApplicationHelper
  # Include route helpers from engines/namespaces needed globally or in test contexts
  include BusinessManager::Engine.routes.url_helpers if defined?(BusinessManager::Engine)
  # Or if it's just a namespace, not a full engine:
  include Rails.application.routes.url_helpers
  # Add specific namespace helpers if needed and the above doesn't work
  # include BusinessManager::ServicesHelper # Example, might not be needed

  # ... existing helper methods ...
end
