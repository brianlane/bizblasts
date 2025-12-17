# frozen_string_literal: true

require 'net/http'
require 'json'

module EmailMarketing
  # Base API client with shared functionality
  class BaseClient
    attr_reader :connection, :errors

    def initialize(connection)
      @connection = connection
      @errors = []
    end

    def get_lists
      raise NotImplementedError, 'Subclass must implement #get_lists'
    end

    def add_contact(customer, list_id: nil)
      raise NotImplementedError, 'Subclass must implement #add_contact'
    end

    def update_contact(customer, list_id: nil)
      raise NotImplementedError, 'Subclass must implement #update_contact'
    end

    def remove_contact(customer, list_id: nil)
      raise NotImplementedError, 'Subclass must implement #remove_contact'
    end

    def get_contact(email, list_id: nil)
      raise NotImplementedError, 'Subclass must implement #get_contact'
    end

    def batch_add_contacts(customers, list_id: nil)
      raise NotImplementedError, 'Subclass must implement #batch_add_contacts'
    end

    protected

    def http_request(method, url, body: nil, headers: {})
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 60
      http.open_timeout = 10

      request = case method
                when :get then Net::HTTP::Get.new(uri)
                when :post then Net::HTTP::Post.new(uri)
                when :put then Net::HTTP::Put.new(uri)
                when :patch then Net::HTTP::Patch.new(uri)
                when :delete then Net::HTTP::Delete.new(uri)
                else raise ArgumentError, "Unknown HTTP method: #{method}"
                end

      default_headers.merge(headers).each { |key, value| request[key] = value }
      request.body = body.is_a?(String) ? body : body.to_json if body

      response = http.request(request)
      parsed_body = parse_response(response)

      ApiResponse.new(
        success: response.code.to_i.between?(200, 299),
        status: response.code.to_i,
        body: parsed_body,
        raw_response: response
      )
    rescue StandardError => e
      @errors << "HTTP request failed: #{e.message}"
      Rails.logger.error "[#{self.class.name}] HTTP request failed: #{e.message}"
      ApiResponse.new(success: false, status: 0, body: { 'error' => e.message }, raw_response: nil)
    end

    def parse_response(response)
      return {} if response.body.blank?
      JSON.parse(response.body)
    rescue JSON::ParserError
      { 'raw' => response.body }
    end

    def default_headers
      raise NotImplementedError, 'Subclass must implement #default_headers'
    end

    def add_error(message)
      @errors << message
      Rails.logger.error "[#{self.class.name}] #{message}"
      # Return a failure hash so callers using `return add_error(...)` get a valid result
      { success: false, error: message }
    end

    # Simple struct for API responses
    class ApiResponse
      attr_reader :status, :body, :raw_response

      def initialize(success:, status:, body:, raw_response:)
        @success = success
        @status = status
        @body = body
        @raw_response = raw_response
      end

      def success?
        @success
      end

      def error_message
        return nil if success?
        body['error'] || body['detail'] || body['error_message'] || body['title'] || 'Unknown error'
      end
    end
  end
end
