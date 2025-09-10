# frozen_string_literal: true

require 'net/http'
require 'uri'

# Service for checking if a custom domain is properly responding with HTTP 200
# This ensures domains are not activated until they're actually serving content
class DomainHealthChecker
  class HealthCheckError < StandardError; end

  # Timeout for HTTP requests (in seconds)
  REQUEST_TIMEOUT = 10
  
  # Follow up to 3 redirects
  MAX_REDIRECTS = 3

  def initialize(domain_name)
    @domain_name = domain_name.to_s.strip.downcase
  end

  # Check if domain responds with HTTP 200
  # @return [Hash] Result with health status and details
  def check_health
    Rails.logger.info "[DomainHealthChecker] Checking health for: #{@domain_name}"

    begin
      result = {
        domain: @domain_name,
        healthy: false,
        status_code: nil,
        response_time: nil,
        final_url: nil,
        redirect_count: 0,
        error: nil,
        checked_at: Time.current
      }

      start_time = Time.current
      response = perform_request(build_url(@domain_name))
      result[:response_time] = (Time.current - start_time).round(3)

      # Handle the response
      if response[:success]
        result[:healthy] = response[:status_code] == 200
        result[:status_code] = response[:status_code]
        result[:final_url] = response[:final_url]
        result[:redirect_count] = response[:redirect_count]

        if result[:healthy]
          Rails.logger.info "[DomainHealthChecker] Domain is healthy: #{@domain_name} (#{response[:status_code]} in #{result[:response_time]}s)"
        else
          Rails.logger.warn "[DomainHealthChecker] Domain returned non-200 status: #{@domain_name} (#{response[:status_code]})"
        end
      else
        result[:error] = response[:error]
        Rails.logger.warn "[DomainHealthChecker] Health check failed for #{@domain_name}: #{response[:error]}"
      end

      result
    rescue => e
      Rails.logger.error "[DomainHealthChecker] Health check exception for #{@domain_name}: #{e.message}"
      {
        domain: @domain_name,
        healthy: false,
        status_code: nil,
        response_time: nil,
        final_url: nil,
        redirect_count: 0,
        error: "Health check exception: #{e.message}",
        checked_at: Time.current
      }
    end
  end

  # Check both HTTP and HTTPS versions of the domain
  # @return [Hash] Combined results for both protocols
  def check_health_both_protocols
    https_result = check_health_for_protocol('https')
    http_result = check_health_for_protocol('http')

    # Prefer HTTPS result, but accept HTTP if HTTPS fails
    primary_result = https_result[:healthy] ? https_result : http_result
    
    {
      domain: @domain_name,
      healthy: https_result[:healthy] || http_result[:healthy],
      primary_protocol: primary_result[:protocol],
      https_result: https_result,
      http_result: http_result,
      checked_at: Time.current
    }
  end

  # Get detailed health information for debugging
  # @return [Hash] Comprehensive health information
  def health_debug_info
    info = {
      domain: @domain_name,
      checked_at: Time.current,
      protocols: {}
    }

    ['https', 'http'].each do |protocol|
      begin
        result = check_health_for_protocol(protocol)
        info[:protocols][protocol] = result
      rescue => e
        info[:protocols][protocol] = {
          protocol: protocol,
          healthy: false,
          error: e.message
        }
      end
    end

    # Also include DNS resolution info
    begin
      addresses = Resolv.getaddresses(@domain_name)
      info[:dns_resolution] = {
        resolved: addresses.any?,
        addresses: addresses
      }
    rescue => e
      info[:dns_resolution] = {
        resolved: false,
        error: e.message
      }
    end

    info
  end

  private

  # Check health for a specific protocol
  def check_health_for_protocol(protocol)
    original_domain = @domain_name
    @domain_name = original_domain # Reset in case it was modified
    
    url = "#{protocol}://#{@domain_name}"
    result = perform_request(url)
    result[:protocol] = protocol
    result
  ensure
    @domain_name = original_domain # Ensure domain is reset
  end

  # Build URL with HTTPS as default
  def build_url(domain, protocol = 'https')
    "#{protocol}://#{domain}"
  end

  # Perform HTTP request with redirect following
  def perform_request(url, redirect_count = 0)
    return { success: false, error: 'Too many redirects' } if redirect_count > MAX_REDIRECTS

    uri = URI(url)
    
    # Create HTTP client
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    
    # Set timeouts
    http.open_timeout = REQUEST_TIMEOUT
    http.read_timeout = REQUEST_TIMEOUT
    
    # Disable SSL verification in development/test to avoid certificate issues
    if Rails.env.development? || Rails.env.test?
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end

    # Create request
    request = Net::HTTP::Get.new(uri)
    
    # Set User-Agent to identify our health check
    request['User-Agent'] = 'BizBlasts-HealthChecker/1.0'
    
    # Set timeout-friendly headers
    request['Accept'] = 'text/html,*/*'
    request['Connection'] = 'close'

    # Perform the request
    response = http.request(request)

    # Handle redirects
    if response.is_a?(Net::HTTPRedirection)
      location = response['Location']
      if location.present?
        # Handle relative redirects
        redirect_uri = location.start_with?('http') ? location : URI.join(url, location).to_s
        Rails.logger.debug "[DomainHealthChecker] Following redirect: #{url} -> #{redirect_uri}"
        return perform_request(redirect_uri, redirect_count + 1)
      end
    end

    {
      success: true,
      status_code: response.code.to_i,
      final_url: url,
      redirect_count: redirect_count,
      headers: response.to_hash,
      error: nil
    }

  rescue Net::ReadTimeout, Net::OpenTimeout => e
    { success: false, error: "Request timeout: #{e.message}" }
  rescue Net::HTTPError => e
    { success: false, error: "HTTP error: #{e.message}" }
  rescue SocketError => e
    { success: false, error: "DNS/Socket error: #{e.message}" }
  rescue OpenSSL::SSL::SSLError => e
    { success: false, error: "SSL error: #{e.message}" }
  rescue => e
    { success: false, error: "Unexpected error: #{e.message}" }
  end
end