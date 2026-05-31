# frozen_string_literal: true

module Api
  module V1
    # Endpoint used by Caddy's `on_demand_tls { ask ... }` directive to decide
    # whether to issue a Let's Encrypt cert for an incoming SNI hostname.
    #
    # Caddy sends:
    #   GET /api/v1/custom_domains/verify?domain=<sni>
    # and only inspects the HTTP status code:
    #   - 2xx => allowed (Caddy will request a cert and serve traffic)
    #   - any other status => denied
    #
    # We delegate to AllowedHostService, which already authorizes apex/www,
    # *.bizblasts.com tenant subdomains, and active custom-domain businesses.
    class CustomDomainsController < ApiController
      skip_before_action :enforce_json_format, raise: false

      # Allow plain HTTP from Caddy/localhost callbacks; this endpoint never
      # returns a body so there is nothing to leak.
      def verify
        unless localhost_request?
          Rails.logger.warn "[CustomDomainsController] verify rejected remote_addr=#{request.env['REMOTE_ADDR'].inspect} remote_ip=#{request.remote_ip.inspect} xff=#{request.env['HTTP_X_FORWARDED_FOR'].inspect}"
          return head :forbidden
        end

        domain = params[:domain].to_s.strip.downcase
        return head :bad_request if domain.blank?

        if AllowedHostService.allowed?(domain)
          Rails.logger.debug "[CustomDomainsController] verify allow domain=#{domain}"
          head :ok
        else
          Rails.logger.info "[CustomDomainsController] verify deny domain=#{domain}"
          head :not_found
        end
      end

      private

      # Caddy is the *only* legitimate caller of this endpoint, and it always
      # calls us with TWO loopback signals:
      #
      #   1. REMOTE_ADDR is a 127.0.0.0/8 / ::1 peer (Caddy → Puma over loopback).
      #   2. The Host header is `localhost` or `127.0.0.1` (Caddy's on_demand_tls
      #      `ask` HTTP client targets `http://localhost:3000/api/v1/...`).
      #
      # Requiring BOTH closes Bugbot MEDIUM ("Verify endpoint trusts all
      # proxies"): if Puma sits behind ANOTHER reverse proxy on the same host
      # (or simply behind Caddy serving a real customer hostname), every
      # external request also has a loopback REMOTE_ADDR — but its Host
      # header is the public hostname, not `localhost`. That host mismatch
      # now rejects external traffic.
      #
      # We use REMOTE_ADDR (not request.remote_ip) because the cloudflare-rails
      # trusted-proxy chain rewrites remote_ip to the upstream CDN IP.
      def localhost_request?
        peer = request.env['REMOTE_ADDR'].to_s
        loopback_peer = peer == '127.0.0.1' || peer == '::1' || peer.start_with?('127.')
        return false unless loopback_peer

        host = request.host.to_s.downcase
        host == 'localhost' || host == '127.0.0.1' || host == '::1'
      end
    end
  end
end
