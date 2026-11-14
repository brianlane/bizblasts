# frozen_string_literal: true

# Cloudflare Rails gem configuration.
#
# The gem treats Cloudflare's published ranges as trusted proxies and patches
# request.ip / request.remote_ip. On this box the TCP peer is Caddy on
# loopback, not a Cloudflare address, so those ranges never match the socket.
# Middleware::LocalProxyClientIp restores the visitor from CF-Connecting-IP
# and X-Forwarded-For only when REMOTE_ADDR is loopback.

Rails.logger.info "[Cloudflare] Using cloudflare-rails gem for Cloudflare proxy ranges"
