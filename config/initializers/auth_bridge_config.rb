# frozen_string_literal: true

# Configuration for authentication bridge system
Rails.application.configure do
  # Auth bridge configuration
  config.x.auth_bridge = ActiveSupport::OrderedOptions.new

  # Token TTL (time to live) - how long auth bridge tokens remain valid
  config.x.auth_bridge.token_ttl = 1.minute

  # Session blacklist TTL - how long invalidated sessions remain in blacklist
  config.x.auth_bridge.session_blacklist_ttl = 24.hours

  # Device fingerprint strict mode - can be made stricter later for enhanced security
  config.x.auth_bridge.device_fingerprint_strict = false # Can make stricter later
end