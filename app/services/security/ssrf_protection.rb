# frozen_string_literal: true

module Security
  # SSRF (Server-Side Request Forgery) Protection
  #
  # Validates URLs before making HTTP requests to prevent attackers from:
  # - Accessing internal network resources
  # - Scanning internal ports
  # - Accessing cloud metadata endpoints
  # - Leaking API keys or credentials
  #
  # Usage:
  #   Security::SsrfProtection.validate_url!(user_provided_url)
  #
  class SsrfProtection
    class SsrfError < StandardError; end

    # Private IP ranges that should be blocked
    PRIVATE_IP_RANGES = [
      IPAddr.new('10.0.0.0/8'),        # Private network
      IPAddr.new('172.16.0.0/12'),     # Private network
      IPAddr.new('192.168.0.0/16'),    # Private network
      IPAddr.new('127.0.0.0/8'),       # Loopback
      IPAddr.new('169.254.0.0/16'),    # Link-local (AWS metadata)
      IPAddr.new('::1/128'),           # IPv6 loopback
      IPAddr.new('fc00::/7'),          # IPv6 private
      IPAddr.new('fe80::/10')          # IPv6 link-local
    ].freeze

    # Cloud metadata endpoints that should be blocked
    METADATA_ENDPOINTS = [
      '169.254.169.254',               # AWS, Azure, GCP metadata
      'metadata.google.internal',      # GCP metadata
      '100.100.100.200'                # Alibaba Cloud metadata
    ].freeze

    # Validate a URL for SSRF vulnerabilities
    # @param url [String] The URL to validate
    # @param allowed_protocols [Array<String>] Allowed protocols (default: ['https'])
    # @raise [SsrfError] If the URL is potentially dangerous
    # @return [URI] Parsed URI object if valid
    def self.validate_url!(url, allowed_protocols: ['https'])
      raise SsrfError, 'URL cannot be blank' if url.blank?

      # Parse the URL
      uri = begin
        URI.parse(url)
      rescue URI::InvalidURIError => e
        raise SsrfError, "Invalid URL format: #{e.message}"
      end

      # Validate protocol
      unless allowed_protocols.include?(uri.scheme)
        raise SsrfError, "Protocol '#{uri.scheme}' not allowed. Only #{allowed_protocols.join(', ')} allowed."
      end

      # Ensure host is present
      raise SsrfError, 'URL must include a hostname' if uri.host.blank?

      # Validate the hostname doesn't resolve to private IPs
      validate_hostname!(uri.host)

      uri
    end

    # Validate that a hostname doesn't resolve to private/metadata IPs
    # @param hostname [String] The hostname to validate
    # @raise [SsrfError] If the hostname resolves to a blocked IP
    def self.validate_hostname!(hostname)
      # Remove brackets from IPv6 addresses (e.g., [::1] -> ::1)
      cleaned_hostname = hostname.gsub(/^\[|\]$/, '')

      # Check if hostname is a metadata endpoint
      if METADATA_ENDPOINTS.include?(cleaned_hostname.downcase)
        raise SsrfError, "Access to metadata endpoint '#{hostname}' is not allowed"
      end

      # Check if hostname is already an IP address
      ip_addresses = if looks_like_ip?(cleaned_hostname)
        # Validate the IP directly without DNS resolution
        [cleaned_hostname]
      else
        # Resolve hostname to IP addresses
        begin
          Resolv.getaddresses(cleaned_hostname)
        rescue Resolv::ResolvError => e
          raise SsrfError, "Could not resolve hostname '#{hostname}': #{e.message}"
        end
      end

      raise SsrfError, "Hostname '#{hostname}' does not resolve to any IP addresses" if ip_addresses.empty?

      # Check each resolved IP address
      ip_addresses.each do |ip_string|
        begin
          ip = IPAddr.new(ip_string)

          # Check if IP is in any private range
          PRIVATE_IP_RANGES.each do |private_range|
            if private_range.include?(ip)
              raise SsrfError, "Access to private IP address '#{ip_string}' is not allowed"
            end
          end
        rescue IPAddr::InvalidAddressError => e
          raise SsrfError, "Invalid IP address '#{ip_string}': #{e.message}"
        end
      end

      true
    end

    # Check if a string looks like an IP address (IPv4 or IPv6)
    # @param str [String] The string to check
    # @return [Boolean] True if it looks like an IP address
    def self.looks_like_ip?(str)
      # Try to parse as IP address
      IPAddr.new(str)
      true
    rescue IPAddr::InvalidAddressError
      false
    end

    # Safe wrapper for making HTTP requests with SSRF protection
    # @param url [String] The URL to request
    # @param allowed_protocols [Array<String>] Allowed protocols
    # @yield Block that receives the validated URI and should make the HTTP request
    # @return The result of the block
    def self.safe_request(url, allowed_protocols: ['https'])
      validated_uri = validate_url!(url, allowed_protocols: allowed_protocols)

      # Double-check before making request (prevents DNS rebinding)
      validate_hostname!(validated_uri.host)

      yield(validated_uri)
    end
  end
end
