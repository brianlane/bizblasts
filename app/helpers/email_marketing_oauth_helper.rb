# frozen_string_literal: true

# Helper module for email marketing OAuth operations
# Centralizes URL building logic to avoid duplication across controllers
module EmailMarketingOauthHelper
  extend self

  # Build OAuth callback URL for email marketing providers
  # Used by both the initiating controller and the callback controller
  #
  # @param provider [String] 'mailchimp' or 'constant-contact'
  # @param request [ActionDispatch::Request] The current request object
  # @return [String] The full callback URL
  def callback_url(provider, request)
    scheme = request.ssl? ? 'https' : 'http'
    host = Rails.application.config.main_domain.presence || request.host
    port_str = build_port_string(host, request.port)
    "#{scheme}://#{host}#{port_str}/oauth/email-marketing/#{provider}/callback"
  end

  # Verify and extract flash message data from signed URL parameter
  # Returns nil if invalid, expired, or missing
  #
  # @param signed_data [String, nil] The signed flash message from URL params
  # @return [Hash, nil] The flash message data (notice:, alert:) or nil
  def verify_flash_message(signed_data)
    return nil if signed_data.blank?

    begin
      message_data = Rails.application.message_verifier(:oauth_flash).verify(signed_data)

      # Check for expiry (5 minutes)
      timestamp = message_data['timestamp'] || message_data[:timestamp]
      if timestamp.present? && Time.current.to_i - timestamp.to_i > 5.minutes.to_i
        Rails.logger.debug "[EmailMarketingOauthHelper] Flash message expired"
        return nil
      end

      message_data.with_indifferent_access
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      Rails.logger.warn "[EmailMarketingOauthHelper] Invalid flash message signature"
      nil
    rescue StandardError => e
      Rails.logger.error "[EmailMarketingOauthHelper] Error verifying flash message: #{e.message}"
      nil
    end
  end

  private

  def build_port_string(host, port)
    return '' if host&.include?(':')
    return '' if port.nil? || [80, 443].include?(port)
    ":#{port}"
  end
end
