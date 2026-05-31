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

      # Caddy and the deploy webhook both run on the same host as Puma. We use
      # the raw TCP peer address (REMOTE_ADDR) rather than `request.remote_ip`
      # because the latter is rewritten by the cloudflare-rails trusted-proxy
      # chain and would treat us as the upstream CDN IP, not the loopback
      # peer that Caddy actually came in on.
      def localhost_request?
        peer = request.env['REMOTE_ADDR'].to_s
        peer == '127.0.0.1' || peer == '::1' || peer.start_with?('127.')
      end
    end
  end
end
