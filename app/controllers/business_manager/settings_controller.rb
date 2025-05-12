# frozen_string_literal: true

# Controller for business settings.
class BusinessManager::SettingsController < BusinessManager::BaseController
  # Include URL helpers in views
  helper Rails.application.routes.url_helpers

  def index
    # Render settings view
  end
end 