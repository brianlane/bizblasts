# frozen_string_literal: true

require 'httparty'

module Quickbooks
  class Client
    include HTTParty

    API_HOST = 'https://quickbooks.api.intuit.com'
    DEFAULT_MINORVERSION = 70

    # Error raised when path validation fails (SSRF protection)
    class InvalidPathError < StandardError; end

    def initialize(connection)
      @connection = connection
    end

    def realm_id
      @connection.realm_id
    end

    def get(path, query: {})
      request(:get, path, query: query)
    end

    def post(path, body: {}, query: {})
      request(:post, path, query: query, body: body)
    end

    def query(q)
      get("/v3/company/#{realm_id}/query", query: { query: q, minorversion: DEFAULT_MINORVERSION })
    end

    private

    def request(method, path, query: {}, body: nil)
      # Validate path to prevent SSRF via absolute URL injection
      # See: GHSA-c8v7-pv9q-f8rw - httparty ignores base_uri for absolute URLs
      validate_path!(path)

      url = API_HOST + path

      headers = {
        'Authorization' => "Bearer #{@connection.access_token}",
        'Accept' => 'application/json',
        'Content-Type' => 'application/json'
      }

      options = { headers: headers, query: query }
      options[:body] = body.to_json if body

      response = self.class.send(method, url, **options)

      if response.code.to_i >= 400
        raise Quickbooks::RequestError.new(response)
      end

      response.parsed_response
    end

    # Validate that path is relative and doesn't contain absolute URL injection
    # This prevents SSRF attacks where httparty follows absolute URLs in path
    def validate_path!(path)
      raise InvalidPathError, 'Path cannot be nil' if path.nil?

      # Path must start with / (relative path)
      unless path.start_with?('/')
        raise InvalidPathError, "Path must be relative (start with /): #{path}"
      end

      # Check for absolute URL patterns that could bypass base_uri
      # httparty will follow these URLs ignoring the configured API_HOST
      absolute_url_patterns = [
        %r{^/+https?://}i,           # //http:// or /https://
        %r{^https?://}i,             # http:// or https://
        %r{^//[^/]}                  # Protocol-relative URL //example.com
      ]

      absolute_url_patterns.each do |pattern|
        if path.match?(pattern)
          raise InvalidPathError, "Absolute URL detected in path (potential SSRF): #{path}"
        end
      end

      true
    end
  end

  class RequestError < StandardError
    attr_reader :response

    def initialize(response)
      @response = response
      super(build_message)
    end

    def build_message
      code = response.code
      body = response.body.to_s
      "QuickBooks API request failed (#{code}): #{body.tr("\n", ' ')[0, 500]}"
    end
  end
end
