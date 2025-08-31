# frozen_string_literal: true

require 'net/http'
require 'json'

# Service for interacting with Render.com Custom Domain API
# Provides methods to add, verify, list, and remove custom domains
class RenderDomainService
  class RenderApiError < StandardError; end
  class DomainNotFoundError < RenderApiError; end
  class InvalidCredentialsError < RenderApiError; end
  class RateLimitError < RenderApiError; end

  API_BASE_URL = 'https://api.render.com/v1'
  
  # Retry configuration for rate limiting (429 responses)
  MAX_RETRIES = 3
  BASE_DELAY = 2 # seconds
  MAX_DELAY = 60 # seconds

  def initialize
    @api_key = ENV['RENDER_API_KEY']
    @service_id = ENV['RENDER_SERVICE_ID']
    
    raise InvalidCredentialsError, 'RENDER_API_KEY not configured' if @api_key.blank?
    raise InvalidCredentialsError, 'RENDER_SERVICE_ID not configured' if @service_id.blank?
  end

  # Add a custom domain to the Render service
  # @param domain_name [String] The domain name to add (e.g., 'example.com')
  # @return [Hash] Response from Render API with domain details
  def add_domain(domain_name)
    Rails.logger.info "[RenderDomainService] Adding domain: #{domain_name}"
    
    url = URI("#{API_BASE_URL}/services/#{@service_id}/custom-domains")
    
    response = make_request(url, :post, { name: domain_name })
    
    if response.code.start_with?('2')
      begin
        domain_data = JSON.parse(response.body)
      rescue JSON::ParserError
        raise RenderApiError, "Unexpected Render response format: #{response.body.inspect}"
      end

      unless domain_data.is_a?(Hash) && domain_data['id']
        raise RenderApiError, "Missing domain id in Render response: #{domain_data.inspect}"
      end

      Rails.logger.info "[RenderDomainService] Domain added successfully: #{domain_data['id']}"
      domain_data
    else
      error_msg = extract_error_message(response)
      Rails.logger.error "[RenderDomainService] Failed to add domain: #{error_msg}"
      raise RenderApiError, "Failed to add domain: #{error_msg}"
    end
  end

  # Verify domain DNS configuration
  # @param domain_id [String] The Render domain ID
  # @return [Hash] Verification status and details
  def verify_domain(domain_id)
    Rails.logger.info "[RenderDomainService] Verifying domain: #{domain_id}"
    
    url = URI("#{API_BASE_URL}/services/#{@service_id}/custom-domains/#{domain_id}/verify")
    
    response = make_request(url, :post, {})
    
    if response.code.start_with?('2')
      verification_data = JSON.parse(response.body)
      Rails.logger.info "[RenderDomainService] Domain verification result: #{verification_data['verified']}"
      verification_data
    else
      error_msg = extract_error_message(response)
      Rails.logger.error "[RenderDomainService] Failed to verify domain: #{error_msg}"
      raise RenderApiError, "Failed to verify domain: #{error_msg}"
    end
  end

  # List all custom domains for the service
  # @return [Array<Hash>] Array of domain objects
  def list_domains
    Rails.logger.info "[RenderDomainService] Listing domains"
    
    url = URI("#{API_BASE_URL}/services/#{@service_id}/custom-domains")
    
    response = make_request(url, :get)
    
    if response.code.start_with?('2')
      domains = JSON.parse(response.body)
      Rails.logger.info "[RenderDomainService] Found #{domains.length} domains"
      domains
    else
      error_msg = extract_error_message(response)
      Rails.logger.error "[RenderDomainService] Failed to list domains: #{error_msg}"
      raise RenderApiError, "Failed to list domains: #{error_msg}"
    end
  end

  # Remove a custom domain from the service
  # @param domain_id [String] The Render domain ID
  # @return [Boolean] True if successful
  def remove_domain(domain_id)
    Rails.logger.info "[RenderDomainService] Removing domain: #{domain_id}"
    
    url = URI("#{API_BASE_URL}/services/#{@service_id}/custom-domains/#{domain_id}")
    
    response = make_request(url, :delete)
    
    if response.code.start_with?('2')
      Rails.logger.info "[RenderDomainService] Domain removed successfully"
      true
    else
      error_msg = extract_error_message(response)
      Rails.logger.error "[RenderDomainService] Failed to remove domain: #{error_msg}"
      raise RenderApiError, "Failed to remove domain: #{error_msg}"
    end
  end

  # Find domain by name in the service's custom domains
  # @param domain_name [String] The domain name to find
  # @return [Hash, nil] Domain object if found, nil otherwise
  def find_domain_by_name(domain_name)
    domains = list_domains
    domains.find { |domain| domain['name'] == domain_name }
  end

  # Check if domain exists and is verified
  # @param domain_name [String] The domain name to check
  # @return [Hash] Status information
  def domain_status(domain_name)
    domain = find_domain_by_name(domain_name)
    
    if domain.nil?
      { exists: false, verified: false, domain_id: nil }
    else
      { 
        exists: true, 
        verified: domain['verified'] == true,
        domain_id: domain['id'],
        domain_data: domain
      }
    end
  end

  private

  # Make HTTP request to Render API with retry logic for rate limiting
  # @param url [URI] The request URL
  # @param method [Symbol] HTTP method (:get, :post, :delete)
  # @param body [Hash, nil] Request body for POST requests
  # @return [Net::HTTPResponse] HTTP response
  def make_request(url, method, body = nil)
    retry_count = 0
    
    loop do
      begin
        response = execute_request(url, method, body)
        
        # Handle rate limiting (429) with exponential backoff
        if response.code == '429'
          if retry_count < MAX_RETRIES
            delay = calculate_retry_delay(retry_count, response)
            Rails.logger.warn "[RenderDomainService] Rate limited (429), retrying in #{delay}s (attempt #{retry_count + 1}/#{MAX_RETRIES + 1})"
            sleep(delay)
            retry_count += 1
            next
          else
            Rails.logger.error "[RenderDomainService] Max retries exceeded for rate limit"
            raise RateLimitError, "Rate limit exceeded after #{MAX_RETRIES} retries"
          end
        end
        
        # Log response status
        Rails.logger.debug "[RenderDomainService] Response: #{response.code}"
        return response
        
      rescue RateLimitError
        # Re-raise rate limit errors without wrapping them
        raise
      rescue => e
        Rails.logger.error "[RenderDomainService] Request failed: #{e.message}"
        raise RenderApiError, "Request failed: #{e.message}"
      end
    end
  end

  # Execute a single HTTP request
  # @param url [URI] The request URL
  # @param method [Symbol] HTTP method (:get, :post, :delete)
  # @param body [Hash, nil] Request body for POST requests
  # @return [Net::HTTPResponse] HTTP response
  def execute_request(url, method, body = nil)
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true

    case method
    when :get
      request = Net::HTTP::Get.new(url)
    when :post
      request = Net::HTTP::Post.new(url)
      if body
        request.body = body.to_json
        request['Content-Type'] = 'application/json'
      end
    when :delete
      request = Net::HTTP::Delete.new(url)
    else
      raise ArgumentError, "Unsupported HTTP method: #{method}"
    end

    # Add authentication header
    request['Accept'] = 'application/json'
    request['Authorization'] = "Bearer #{@api_key}"

    # Log request (without sensitive data)
    Rails.logger.debug "[RenderDomainService] #{method.upcase} #{url.path}"

    http.request(request)
  end

  # Calculate retry delay using exponential backoff with jitter
  # @param retry_count [Integer] Current retry attempt (0-based)
  # @param response [Net::HTTPResponse] The 429 response (may contain Retry-After header)
  # @return [Float] Delay in seconds
  def calculate_retry_delay(retry_count, response)
    # Check for Retry-After header first
    if response['Retry-After']
      retry_after = response['Retry-After'].to_i
      return [retry_after, MAX_DELAY].min if retry_after > 0
    end
    
    # Use exponential backoff with jitter
    base_delay = BASE_DELAY * (2 ** retry_count)
    jitter = rand * base_delay * 0.1 # Add up to 10% jitter
    delay = base_delay + jitter
    
    [delay, MAX_DELAY].min
  end

  # Extract error message from API response
  # @param response [Net::HTTPResponse] HTTP response
  # @return [String] Error message
  def extract_error_message(response)
    return "HTTP #{response.code}" if response.body.blank?

    begin
      error_data = JSON.parse(response.body)
      error_data['message'] || error_data['error'] || "HTTP #{response.code}"
    rescue JSON::ParserError
      "HTTP #{response.code}: #{response.body.truncate(100)}"
    end
  end
end