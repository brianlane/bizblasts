# frozen_string_literal: true

# Cloudflare Rails gem configuration
# This gem automatically configures trusted proxies for Cloudflare's IP ranges
# and keeps them updated, allowing request.remote_ip to return the real client IP

# The gem automatically handles trusted proxy configuration in production
# No additional configuration needed - it fetches Cloudflare's current IP ranges

Rails.logger.info "[Cloudflare] Using cloudflare-rails gem for automatic trusted proxy configuration"
