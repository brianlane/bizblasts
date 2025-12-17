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

  private

  def build_port_string(host, port)
    return '' if host&.include?(':')
    return '' if port.nil? || [80, 443].include?(port)
    ":#{port}"
  end
end
