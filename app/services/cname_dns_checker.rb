# frozen_string_literal: true

require 'resolv'

# Service for verifying CNAME DNS configuration
# Checks if a custom domain properly points to Render's infrastructure
class CnameDnsChecker
  class DnsResolutionError < StandardError; end

  # Targets that indicate correct routing to Render
  RENDER_CNAME_TARGET = Rails.env.production? ? 'bizblasts.onrender.com' : 'localhost'

  # Render's apex IP for A record verification (DIFFERENT from outbound IPs)
  # This is the IP that custom domains should point their A records to
  # NOTE: This is NOT the same as Render's outbound IP addresses that changed Oct 2025
  # Check Render docs or contact support if this needs updating: https://render.com/docs/custom-domains
  # TODO: Consider making this configurable via ENV['RENDER_APEX_IP'] for easier updates
  RENDER_APEX_IP = ENV['RENDER_APEX_IP'] || '216.24.57.1'

  # Provider-aware verification targets. On the Caddy/Ubuntu deployment the
  # customer's apex A record (and the www A record) must point at our public
  # IP — there is no CNAME-to-onrender step. On Render we keep the legacy
  # CNAME-to-onrender + apex-A-to-216.24.57.1 contract.
  # (Bugbot HIGH: DNS checks ignore Caddy targets.)
  def self.expected_cname_target
    return nil if defined?(DomainProvider) && DomainProvider.caddy?
    RENDER_CNAME_TARGET
  end

  def self.expected_apex_ip
    if defined?(DomainProvider) && DomainProvider.caddy?
      ENV['BIZBLASTS_PUBLIC_IP'].to_s.strip.presence || resolve_bizblasts_a
    else
      RENDER_APEX_IP
    end
  end

  # Fallback: if BIZBLASTS_PUBLIC_IP isn't set, derive the target from a live
  # lookup of bizblasts.com itself (since the customer's apex is meant to
  # point at the same host). Best-effort; nil on failure.
  def self.resolve_bizblasts_a
    Resolv::DNS.open do |r|
      r.getresources('bizblasts.com', Resolv::DNS::Resource::IN::A).first&.address&.to_s
    end
  rescue StandardError
    nil
  end

  def initialize(domain_name)
    @domain_name = domain_name.to_s.strip.downcase
    @resolver = Resolv::DNS.new
  end

  # Check if the domain's CNAME points to the correct target
  # @return [Hash] Result with verification status and details
  def verify_cname
    Rails.logger.info "[CnameDnsChecker] Checking CNAME for: #{@domain_name}"

    expected_cname = self.class.expected_cname_target
    expected_ip    = self.class.expected_apex_ip

    begin
      result = {
        domain: @domain_name,
        verified: false,
        target: nil,
        expected_target: expected_cname || expected_ip,
        error: nil,
        checked_at: Time.current
      }

      # On Caddy there is no CNAME-to-onrender step; only A-record verification
      # against BIZBLASTS_PUBLIC_IP matters. Skip CNAME resolution entirely.
      cname_target = expected_cname ? resolve_cname(@domain_name) : nil

      if cname_target.present?
        result[:target] = cname_target
        result[:verified] = cname_matches_target?(cname_target)

        Rails.logger.info "[CnameDnsChecker] CNAME found: #{@domain_name} -> #{cname_target}"
        Rails.logger.info "[CnameDnsChecker] Verification: #{result[:verified] ? 'PASSED' : 'FAILED'}"
      else
        # No CNAME (or CNAME not applicable for provider) — verify via apex A record.
        if apex_a_matches_expected?(@domain_name)
          result[:target] = expected_ip
          result[:verified] = true
          result[:error] = nil
          Rails.logger.info "[CnameDnsChecker] Apex A-record matches expected IP for #{@domain_name}"
        else
          result[:error] = expected_cname ? 'No CNAME record found' : 'A-record does not point at BizBlasts public IP'
          Rails.logger.warn "[CnameDnsChecker] No matching DNS record for: #{@domain_name}"
        end
      end

      result
    rescue => e
      Rails.logger.error "[CnameDnsChecker] DNS resolution failed: #{e.message}"
      {
        domain: @domain_name,
        verified: false,
        target: nil,
        expected_target: expected_cname || expected_ip,
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

    expected = self.class.expected_cname_target
    return false if expected.blank?

    # Normalize targets for comparison
    normalized_target = target.downcase.chomp('.')
    normalized_expected = expected.downcase.chomp('.')

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

  # Determine whether the domain has an A-record that points to the provider's
  # expected apex IP (Render IP on Render, or BIZBLASTS_PUBLIC_IP on Caddy).
  #
  # Per-provider behavior (Bugbot MEDIUM: "WWW DNS checks apex only"):
  #
  # - Render: historic behavior. The www variant is verified via CNAME and we
  #   only fall through to apex-A as a last-resort. In that fallback we accept
  #   apex-A matching even if the caller passed `www.example.com`, because the
  #   customer *must* have an apex A pointing at Render's IP for any traffic
  #   to work and we don't want to flag the domain as broken just because
  #   their www CNAME isn't observable.
  #
  # - Caddy: customers must independently set A records for BOTH apex and www
  #   pointing at BIZBLASTS_PUBLIC_IP. Stripping www and checking only the
  #   apex would mark www.example.com as verified when only the apex points
  #   at us — and the on_demand_tls handshake for www would then 404 because
  #   AllowedHostService would still say no. Check the EXACT host instead.
  def apex_a_matches_expected?(domain)
    expected = self.class.expected_apex_ip
    return false if expected.blank?

    caddy_mode = defined?(DomainProvider) && DomainProvider.caddy?
    name = if caddy_mode
             domain
           else
             domain.start_with?('www.') ? domain.sub('www.', '') : domain
           end

    begin
      a_records = @resolver.getresources(name, Resolv::DNS::Resource::IN::A)
      a_records.map(&:address).map(&:to_s).include?(expected)
    rescue => e
      Rails.logger.warn "[CnameDnsChecker] A-record lookup failed for #{name}: #{e.message}"
      false
    end
  end

  # Backwards-compat alias — older callers / specs may reference the old name.
  alias_method :apex_a_matches_render?, :apex_a_matches_expected?
end