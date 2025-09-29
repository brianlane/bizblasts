# frozen_string_literal: true

# Configuration for authentication event tracking
Rails.application.configure do
  # Enable authentication tracking
  config.x.auth_tracking = ActiveSupport::OrderedOptions.new
  config.x.auth_tracking.enabled = !Rails.env.test? # Disable in test to avoid noise

  # Enable monitoring integration (for external services like DataDog)
  config.x.auth_tracking.monitoring_enabled = Rails.env.production?

  # Enable analytics storage (for custom analytics)
  config.x.auth_tracking.analytics_enabled = Rails.env.production?

  # Log level for auth tracking events
  config.x.auth_tracking.log_level = Rails.env.production? ? :info : :debug
end