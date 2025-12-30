# frozen_string_literal: true

require 'net/http'
require 'uri'

module Analytics
  # HTTP client with timeout and retry logic for external API calls
  # Used by SEO service and other analytics components
  class HttpClient
    class RequestError < StandardError; end
    class TimeoutError < StandardError; end
    class TooManyRedirectsError < StandardError; end

    MAX_REDIRECTS = 5

    def initialize
      @config = Rails.application.config.analytics
    end

    # Make a GET request with timeout and retry
    # @param url [String] The URL to fetch
    # @param options [Hash] Additional options
    # @return [Net::HTTPResponse] The HTTP response
    # @raise [RequestError, TimeoutError] on failure
    def get(url, options = {})
      uri = URI.parse(url)
      retries = options[:retry_attempts] || @config.http_retry_attempts
      timeout = options[:timeout] || @config.http_timeout
      open_timeout = options[:open_timeout] || @config.http_open_timeout

      attempt = 0
      begin
        attempt += 1

        response = make_request(uri, timeout, open_timeout, options)

        # Handle redirects
        if response.is_a?(Net::HTTPRedirection)
          redirect_count = options[:redirect_count] || 0
          raise TooManyRedirectsError, "Too many redirects (#{redirect_count})" if redirect_count >= MAX_REDIRECTS

          location = response['location']
          return get(location, options.merge(redirect_count: redirect_count + 1))
        end

        response

      rescue Timeout::Error, Net::OpenTimeout, Net::ReadTimeout => e
        if attempt < retries
          sleep_time = exponential_backoff(attempt)
          Rails.logger.warn "[HttpClient] Timeout on attempt #{attempt}/#{retries}, retrying in #{sleep_time}s: #{url}"
          sleep(sleep_time)
          retry
        end

        Rails.logger.error "[HttpClient] Timeout after #{retries} attempts: #{url}"
        raise TimeoutError, "Request timeout after #{retries} attempts: #{e.message}"

      rescue Net::HTTPError, SocketError, Errno::ECONNREFUSED => e
        if attempt < retries && retryable_error?(e)
          sleep_time = exponential_backoff(attempt)
          Rails.logger.warn "[HttpClient] Error on attempt #{attempt}/#{retries}, retrying in #{sleep_time}s: #{e.message}"
          sleep(sleep_time)
          retry
        end

        Rails.logger.error "[HttpClient] Request failed: #{url} - #{e.message}"
        raise RequestError, "Request failed: #{e.message}"
      end
    end

    # Make a POST request with timeout and retry
    # @param url [String] The URL to post to
    # @param body [Hash, String] The request body
    # @param options [Hash] Additional options
    # @return [Net::HTTPResponse] The HTTP response
    def post(url, body = nil, options = {})
      uri = URI.parse(url)
      retries = options[:retry_attempts] || @config.http_retry_attempts
      timeout = options[:timeout] || @config.http_timeout
      open_timeout = options[:open_timeout] || @config.http_open_timeout

      attempt = 0
      begin
        attempt += 1

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = open_timeout
        http.read_timeout = timeout

        request = Net::HTTP::Post.new(uri.path)
        request.body = body.is_a?(Hash) ? body.to_json : body
        request['Content-Type'] = 'application/json' if body.is_a?(Hash)

        # Add custom headers
        if options[:headers]
          options[:headers].each { |key, value| request[key] = value }
        end

        http.request(request)

      rescue Timeout::Error, Net::OpenTimeout, Net::ReadTimeout => e
        if attempt < retries
          sleep_time = exponential_backoff(attempt)
          Rails.logger.warn "[HttpClient] POST timeout on attempt #{attempt}/#{retries}, retrying in #{sleep_time}s"
          sleep(sleep_time)
          retry
        end

        raise TimeoutError, "POST timeout after #{retries} attempts: #{e.message}"

      rescue Net::HTTPError, SocketError => e
        if attempt < retries && retryable_error?(e)
          sleep_time = exponential_backoff(attempt)
          Rails.logger.warn "[HttpClient] POST error on attempt #{attempt}/#{retries}, retrying in #{sleep_time}s"
          sleep(sleep_time)
          retry
        end

        raise RequestError, "POST failed: #{e.message}"
      end
    end

    private

    def make_request(uri, timeout, open_timeout, options = {})
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = open_timeout
      http.read_timeout = timeout

      request = Net::HTTP::Get.new(uri.request_uri)

      # Add custom headers
      if options[:headers]
        options[:headers].each { |key, value| request[key] = value }
      end

      # Add user agent
      request['User-Agent'] = options[:user_agent] || 'BizBlasts Analytics/1.0'

      http.request(request)
    end

    def exponential_backoff(attempt)
      # Exponential backoff: 1s, 2s, 4s, etc.
      [2**(attempt - 1), 10].min
    end

    def retryable_error?(error)
      # Only retry on temporary network errors, not on permanent failures
      error.is_a?(Timeout::Error) ||
        error.is_a?(Net::OpenTimeout) ||
        error.is_a?(Net::ReadTimeout) ||
        error.is_a?(Errno::ECONNREFUSED) ||
        error.is_a?(SocketError)
    end
  end
end
