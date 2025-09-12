# frozen_string_literal: true

require 'net/http'
require 'uri'

# Service for checking if a custom domain is properly responding with HTTP 200
# This ensures domains are not activated until they're actually serving content
class DomainHealthChecker
  class HealthCheckError < StandardError; end

  # Timeout for HTTP requests (in seconds) - shorter for faster feedback
  REQUEST_TIMEOUT = 3
  
  # Follow up to 3 redirects
  MAX_REDIRECTS = 3

  def initialize(domain_name)
    @domain_name = domain_name.to_s.strip.downcase
    @memoized_results = {}
  end

  # Check if domain responds with HTTP 200, with SSL-aware fallback
  # @return [Hash] Result with health status and details
  def check_health
    # Return memoized result if available (within same request)
    cache_key = "health_#{@domain_name}"
    return @memoized_results[cache_key] if @memoized_results[cache_key]
    
    Rails.logger.info "[DomainHealthChecker] Checking health for: #{@domain_name}"

    begin
      result = {
        domain: @domain_name,
        healthy: false,
        status_code: nil,
        response_time: nil,
        final_url: nil,
        redirect_count: 0,
        protocol_used: nil,
        ssl_ready: false,
        error: nil,
        checked_at: Time.current
      }

      # Try HTTPS first, but fallback to HTTP if SSL isn't ready
      start_time = Time.current
      https_response = perform_request(build_url(@domain_name, 'https'))
      
      if https_response[:success] && https_response[:status_code] == 200
        # HTTPS works - SSL is ready!
        result.merge!(https_response.except(:success))
        result[:healthy] = true
        result[:protocol_used] = 'https'
        result[:ssl_ready] = true
        result[:response_time] = (Time.current - start_time).round(3)
        Rails.logger.info "[DomainHealthChecker] Domain healthy via HTTPS: #{@domain_name} (#{result[:status_code]} in #{result[:response_time]}s)"
      elsif https_response[:error]&.include?('SSL') || https_response[:error]&.include?('handshake')
        # SSL error - certificate likely not ready yet, try HTTP
        Rails.logger.info "[DomainHealthChecker] SSL not ready for #{@domain_name}, trying HTTP fallback: #{https_response[:error]}"
        
        http_response = perform_request(build_url(@domain_name, 'http'))
        if http_response[:success] && http_response[:status_code] == 200
          # HTTP works - domain is functional but SSL not ready
          result.merge!(http_response.except(:success))
          result[:healthy] = true
          result[:protocol_used] = 'http'
          result[:ssl_ready] = false
          result[:response_time] = (Time.current - start_time).round(3)
          Rails.logger.info "[DomainHealthChecker] Domain healthy via HTTP (SSL pending): #{@domain_name} (#{result[:status_code]} in #{result[:response_time]}s)"
        else
          # Both HTTPS and HTTP failed - this is likely certificate propagation delay
          # If we get SSL handshake failures, the domain routing is correct but cert isn't propagated yet
          if is_ssl_propagation_delay?(https_response[:error], http_response[:error])
            result[:healthy] = true
            result[:protocol_used] = 'https'
            result[:ssl_ready] = false
            result[:error] = "Certificate propagation in progress (SSL handshake failure)"
            result[:response_time] = (Time.current - start_time).round(3)
            result[:propagation_retry_needed] = true  # Signal that retry job should be started
            Rails.logger.info "[DomainHealthChecker] Domain healthy (cert propagating): #{@domain_name} - #{result[:error]}"
          else
            # Both HTTPS and HTTP failed for other reasons
            result[:error] = "HTTPS failed (SSL): #{https_response[:error]}; HTTP failed: #{http_response[:error]}"
            result[:response_time] = (Time.current - start_time).round(3)
            Rails.logger.warn "[DomainHealthChecker] Both HTTPS and HTTP failed for #{@domain_name}: #{result[:error]}"
          end
        end
      else
        # HTTPS failed for non-SSL reasons
        result.merge!(https_response.except(:success))
        result[:protocol_used] = 'https'
        result[:response_time] = (Time.current - start_time).round(3)
        Rails.logger.warn "[DomainHealthChecker] HTTPS failed for #{@domain_name}: #{https_response[:error]}"
      end

      # Cache and return result
      @memoized_results[cache_key] = result
      result
    rescue => e
      Rails.logger.error "[DomainHealthChecker] Health check exception for #{@domain_name}: #{e.message}"
      result = {
        domain: @domain_name,
        healthy: false,
        status_code: nil,
        response_time: nil,
        final_url: nil,
        redirect_count: 0,
        protocol_used: nil,
        ssl_ready: false,
        error: "Health check exception: #{e.message}",
        checked_at: Time.current
      }
      # Cache error result too to avoid repeated failures
      @memoized_results[cache_key] = result
      result
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

  # Detect if errors indicate SSL certificate propagation delay rather than configuration issues
  # @param https_error [String] HTTPS error message
  # @param http_error [String] HTTP error message  
  # @return [Boolean] True if this looks like cert propagation delay
  def is_ssl_propagation_delay?(https_error, http_error)
    # SSL handshake failures typically indicate cert propagation issues
    ssl_handshake_patterns = [
      'handshake failure',
      'SSL_connect returned=1',
      'sslv3 alert handshake failure',
      'SSL_ERROR_SSL',
      'certificate verify failed'
    ]
    
    # HTTP redirect to HTTPS (common when cert is propagating)
    http_redirect_patterns = [
      'Moved Permanently',
      'Found', 
      '301',
      '302',
      '308'
    ]
    
    has_ssl_handshake_error = ssl_handshake_patterns.any? { |pattern| https_error&.include?(pattern) }
    has_http_redirect = http_redirect_patterns.any? { |pattern| http_error&.include?(pattern) }
    
    # If HTTPS has handshake failure and HTTP redirects (or also fails), it's likely propagation
    has_ssl_handshake_error && (has_http_redirect || http_error&.include?('SSL'))
  end

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
    
    # Always use SSL verification for security
    # If there are SSL issues, we'll catch them and return appropriate error messages
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER

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