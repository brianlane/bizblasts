# frozen_string_literal: true

require 'resolv'

# Service for verifying CNAME DNS configuration
# Checks if a custom domain properly points to Render's infrastructure
class CnameDnsChecker
  class DnsResolutionError < StandardError; end

  # Targets that indicate correct routing to Render
  RENDER_CNAME_TARGET = Rails.env.production? ? 'bizblasts.onrender.com' : 'localhost'
  RENDER_APEX_IP       = '216.24.57.1' # Render documented anycast IP for apex A records

  def initialize(domain_name)
    @domain_name = domain_name.to_s.strip.downcase
    @resolver = Resolv::DNS.new
  end

  # Check if the domain's CNAME points to the correct target
  # @return [Hash] Result with verification status and details
  def verify_cname
    Rails.logger.info "[CnameDnsChecker] Checking CNAME for: #{@domain_name}"

    begin
      result = {
        domain: @domain_name,
        verified: false,
        target: nil,
        expected_target: RENDER_CNAME_TARGET,
        error: nil,
        checked_at: Time.current
      }

      # First, try to resolve CNAME for the exact domain
      cname_target = resolve_cname(@domain_name)
      
      if cname_target.present?
        result[:target] = cname_target
        result[:verified] = cname_matches_target?(cname_target)
        
        Rails.logger.info "[CnameDnsChecker] CNAME found: #{@domain_name} -> #{cname_target}"
        Rails.logger.info "[CnameDnsChecker] Verification: #{result[:verified] ? 'PASSED' : 'FAILED'}"
      else
        # If no CNAME exists, allow apex verification via A/ALIAS pointing to Render IP
        if apex_a_matches_render?(@domain_name)
          result[:target] = RENDER_APEX_IP
          result[:verified] = true
          result[:error] = nil
          Rails.logger.info "[CnameDnsChecker] Apex A-record matches Render IP for #{@domain_name}"
        else
          result[:error] = 'No CNAME record found'
          Rails.logger.warn "[CnameDnsChecker] No CNAME record (and apex A mismatch) for: #{@domain_name}"
        end
      end

      result
    rescue => e
      Rails.logger.error "[CnameDnsChecker] DNS resolution failed: #{e.message}"
      {
        domain: @domain_name,
        verified: false,
        target: nil,
        expected_target: RENDER_CNAME_TARGET,
        error: e.message,
        checked_at: Time.current
      }
    ensure
      @resolver&.close
    end
  end

  # Check multiple DNS servers for more reliable results
  # @return [Hash] Aggregated results from multiple DNS servers
  def verify_cname_multiple_dns
    dns_servers = [
      '8.8.8.8',        # Google DNS
      '1.1.1.1',        # Cloudflare DNS  
      '208.67.222.222'  # OpenDNS
    ]

    results = []
    
    dns_servers.each do |dns_server|
      begin
        resolver = Resolv::DNS.new(nameserver: [dns_server])
        checker = self.class.new(@domain_name)
        checker.instance_variable_set(:@resolver, resolver)
        
        result = checker.verify_cname
        result[:dns_server] = dns_server
        results << result
        
        resolver.close
      rescue => e
        Rails.logger.warn "[CnameDnsChecker] Failed to check DNS server #{dns_server}: #{e.message}"
        results << {
          domain: @domain_name,
          verified: false,
          dns_server: dns_server,
          error: e.message,
          checked_at: Time.current
        }
      end
    end

    # Aggregate results
    verified_count = results.count { |r| r[:verified] }
    total_count = results.length

    {
      domain: @domain_name,
      verified: verified_count > 0,
      verification_ratio: "#{verified_count}/#{total_count}",
      all_verified: verified_count == total_count,
      results: results,
      checked_at: Time.current
    }
  end

  # Get detailed DNS information for debugging
  # @return [Hash] Comprehensive DNS information
  def dns_debug_info
    info = {
      domain: @domain_name,
      checked_at: Time.current,
      records: {}
    }

    # Check different record types
    record_types = ['A', 'CNAME', 'AAAA', 'MX']
    
    record_types.each do |type|
      begin
        records = @resolver.getresources(@domain_name, Resolv::DNS::Resource::IN.const_get(type))
        info[:records][type] = records.map(&:to_s)
      rescue => e
        info[:records][type] = ["Error: #{e.message}"]
      end
    end

    # Also check without www prefix
    if @domain_name.start_with?('www.')
      root_domain = @domain_name.sub('www.', '')
      info[:root_domain_check] = self.class.new(root_domain).verify_cname
    end

    info
  end

  # Check if domain resolves to any IP (basic connectivity test)
  # @return [Boolean] True if domain resolves to an IP
  def domain_resolves?
    begin
      addresses = @resolver.getaddresses(@domain_name)
      addresses.any?
    rescue
      false
    end
  end

  private

  # Resolve CNAME record for the domain
  # @param domain [String] Domain to resolve
  # @return [String, nil] CNAME target or nil if not found
  def resolve_cname(domain)
    cname_records = @resolver.getresources(domain, Resolv::DNS::Resource::IN::CNAME)
    return nil if cname_records.empty?

    # Return the first CNAME target
    cname_records.first.name.to_s.chomp('.')
  end

  # Check if CNAME target matches expected target
  # @param target [String] The resolved CNAME target
  # @return [Boolean] True if target matches expected
  def cname_matches_target?(target)
    return false if target.blank?

    # Normalize targets for comparison
    normalized_target = target.downcase.chomp('.')
    normalized_expected = RENDER_CNAME_TARGET.downcase.chomp('.')

    # Direct match
    return true if normalized_target == normalized_expected

    # In development/test, be more lenient
    unless Rails.env.production?
      return true if normalized_target.include?('localhost') || 
                     normalized_target.include?('127.0.0.1') ||
                     normalized_target.include?('render') ||
                     normalized_target.include?('bizblasts')
    end

    false
  end

  # Determine whether the domain (or its root form) has an A-record that
  # points to Render's apex IP. This is used when an apex cannot use CNAME.
  def apex_a_matches_render?(domain)
    begin
      root = domain.start_with?('www.') ? domain.sub('www.', '') : domain
      a_records = @resolver.getresources(root, Resolv::DNS::Resource::IN::A)
      a_records.map(&:address).map(&:to_s).include?(RENDER_APEX_IP)
    rescue => e
      Rails.logger.warn "[CnameDnsChecker] A-record lookup failed for #{domain}: #{e.message}"
      false
    end
  end
end