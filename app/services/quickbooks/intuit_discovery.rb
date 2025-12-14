# frozen_string_literal: true

require 'net/http'
require 'json'

module Quickbooks
  # Fetches Intuit's OAuth/OIDC discovery document and caches the endpoints.
  #
  # We intentionally keep known-good defaults and fall back to them if discovery
  # is unavailable, so OAuth flows never depend on this network call.
  class IntuitDiscovery
    DISCOVERY_URL = 'https://developer.api.intuit.com/.well-known/openid_configuration'

    DEFAULT_ENDPOINTS = {
      'authorization_endpoint' => 'https://appcenter.intuit.com/connect/oauth2',
      'token_endpoint' => 'https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer',
      'revocation_endpoint' => 'https://developer.api.intuit.com/v2/oauth2/tokens/revoke',
      'jwks_uri' => 'https://oauth.platform.intuit.com/op/v1/jwks',
      'issuer' => 'https://oauth.platform.intuit.com/op/v1'
    }.freeze

    CACHE_TTL = 24.hours

    class << self
      def endpoints
        Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
          discovered = fetch
          normalize(discovered)
        end
      rescue => e
        Rails.logger.warn("[Quickbooks::IntuitDiscovery] Using default endpoints (#{e.class}: #{e.message})")
        DEFAULT_ENDPOINTS
      end

      def fetch
        uri = URI.parse(DISCOVERY_URL)
        response = Net::HTTP.get_response(uri)

        unless response.code.to_s == '200'
          raise "Discovery request failed (status #{response.code})"
        end

        JSON.parse(response.body)
      rescue JSON::ParserError => e
        raise "Discovery JSON parse failed: #{e.message}"
      end

      private

      def cache_key
        env = QuickbooksOauthCredentials.environment rescue Rails.env
        "quickbooks:intuit_openid_configuration:#{env}"
      end

      def normalize(hash)
        h = hash.is_a?(Hash) ? hash : {}

        # Only accept https URLs. If anything is missing/invalid, fall back to defaults.
        required = %w[authorization_endpoint token_endpoint]
        required.each do |k|
          val = h[k].to_s
          raise "Missing #{k}" if val.blank?
          raise "Invalid #{k} scheme" unless val.start_with?('https://')
        end

        DEFAULT_ENDPOINTS.merge(h.slice(*DEFAULT_ENDPOINTS.keys))
      rescue => e
        Rails.logger.warn("[Quickbooks::IntuitDiscovery] Invalid discovery payload; using defaults (#{e.class}: #{e.message})")
        DEFAULT_ENDPOINTS
      end
    end
  end
end
