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

        unless AllowedHostService.allowed?(domain)
          Rails.logger.info "[CustomDomainsController] verify deny (AllowedHostService) domain=#{domain}"
          return head :not_found
        end

        # Defense in depth: AllowedHostService accepts custom_domain businesses
        # in cname_pending state (so the host-routing constraint admits the
        # request once DNS is configured), but Caddy should only mint a cert
        # for a domain that has actually progressed through CnameSetupService —
        # otherwise we'd hand out a Let's Encrypt cert for a hostname that
        # CaddyDomainService and DomainMonitoringService don't track, which
        # Bugbot flagged as "TLS verify allows pre-setup domains". Platform
        # hosts (bizblasts.com, *.bizblasts.com tenant subdomains) always
        # pass through; only registered custom-domain businesses are gated.
        unless platform_host?(domain) || registered_custom_domain?(domain)
          Rails.logger.info "[CustomDomainsController] verify deny (pre-setup custom domain) domain=#{domain}"
          return head :not_found
        end

        Rails.logger.debug "[CustomDomainsController] verify allow domain=#{domain}"
        head :ok
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

      # Platform-owned hostnames that Caddy is always permitted to mint certs
      # for: the apex / www and any tenant subdomain under the primary domain.
      def platform_host?(domain)
        return true if AllowedHostService.main_domain?(domain)
        AllowedHostService.valid_platform_subdomain?(domain)
      end

      # A custom-domain business is "registered" with the provider once
      # CnameSetupService has finished its add_domain step. For Caddy that
      # surfaces in CaddyDomainService#list_domains (which now filters on
      # render_domain_added=true); for Render it's the same flag plus a
      # live API lookup. Reuse find_domain_by_name to share the contract.
      def registered_custom_domain?(domain)
        DomainProvider.current.find_domain_by_name(domain).present?
      rescue StandardError => e
        Rails.logger.warn "[CustomDomainsController] provider lookup failed for #{domain}: #{e.message}"
        false
      end
    end
  end
end
