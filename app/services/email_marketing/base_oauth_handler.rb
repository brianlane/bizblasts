# frozen_string_literal: true

require 'net/http'
require 'json'

module EmailMarketing
  # Base OAuth handler with shared functionality for email marketing integrations
  class BaseOauthHandler
    include ActiveModel::Validations

    attr_reader :errors

    def initialize
      @errors = ActiveModel::Errors.new(self)
    end

    protected

    def generate_state(business_id, provider)
      state_data = {
        business_id: business_id,
        provider: provider,
        timestamp: Time.current.to_i,
        nonce: SecureRandom.hex(16)
      }

      Rails.application.message_verifier(:email_marketing_oauth).generate(state_data)
    end

    def verify_state(state)
      return nil if state.blank?

      begin
        state_data = Rails.application.message_verifier(:email_marketing_oauth).verify(state)

        # 15 minute expiry
        if Time.current.to_i - state_data['timestamp'].to_i > 15.minutes.to_i
          add_error(:expired_state, 'OAuth state expired')
          return nil
        end

        state_data
      rescue ActiveSupport::MessageVerifier::InvalidSignature
        add_error(:invalid_state, 'Invalid OAuth state')
        nil
      rescue StandardError => e
        add_error(:invalid_state, "Error validating OAuth state: #{e.message}")
        nil
      end
    end

    def http_post(url, body, headers = {})
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 30
      http.open_timeout = 10

      request = Net::HTTP::Post.new(uri)
      headers.each { |key, value| request[key] = value }
      request.body = body.is_a?(String) ? body : URI.encode_www_form(body)

      response = http.request(request)
      [response.code.to_i, JSON.parse(response.body)]
    rescue JSON::ParserError
      [response.code.to_i, { 'error' => response.body }]
    rescue StandardError => e
      add_error(:request_failed, "HTTP request failed: #{e.message}")
      [0, { 'error' => e.message }]
    end

    def http_get(url, headers = {})
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 30
      http.open_timeout = 10

      request = Net::HTTP::Get.new(uri)
      headers.each { |key, value| request[key] = value }

      response = http.request(request)
      [response.code.to_i, JSON.parse(response.body)]
    rescue JSON::ParserError
      [response.code.to_i, { 'error' => response.body }]
    rescue StandardError => e
      add_error(:request_failed, "HTTP request failed: #{e.message}")
      [0, { 'error' => e.message }]
    end

    def add_error(type, message)
      @errors.add(type, message)
      Rails.logger.error("[#{self.class.name}] #{type}: #{message}")
    end
  end
end
