# frozen_string_literal: true

# Service for verifying both apex domain (A record) and www subdomain (CNAME record)
# This provides comprehensive domain ownership verification for custom domains
class DualDomainVerifier
  def initialize(domain_name)
    @domain_name = domain_name.to_s.strip.downcase
    @apex_domain = @domain_name.start_with?('www.') ? @domain_name.sub('www.', '') : @domain_name
    @www_domain = "www.#{@apex_domain}"
    @dns_checker = CnameDnsChecker.new(@domain_name)
  end

  # Verify both apex (A record) and www (CNAME record) configurations
  # @return [Hash] Comprehensive verification results
  def verify_both_domains
    Rails.logger.info "[DualDomainVerifier] Verifying both apex and www for: #{@domain_name}"

    begin
      # Check apex domain A record
      apex_result = verify_apex_domain

      # Check www domain CNAME record  
      www_result = verify_www_domain

      # Determine overall verification status
      overall_verified = apex_result[:verified] && www_result[:verified]
      
      www_record_type = CnameDnsChecker.expected_cname_target ? 'CNAME' : 'A'
      result = {
        domain: @domain_name,
        overall_verified: overall_verified,
        apex_domain: {
          domain: @apex_domain,
          verified: apex_result[:verified],
          record_type: 'A',
          target: apex_result[:target],
          expected_target: apex_result[:expected_target],
          error: apex_result[:error]
        },
        www_domain: {
          domain: @www_domain,
          verified: www_result[:verified],
          record_type: www_record_type,
          target: www_result[:target],
          expected_target: www_result[:expected_target],
          error: www_result[:error]
        },
        checked_at: Time.current
      }

      if overall_verified
        Rails.logger.info "[DualDomainVerifier] ✅ Both domains verified successfully"
      else
        # On Caddy www is an A record (not a CNAME), so hardcoding "www CNAME
        # record" here would send Caddy operators down the wrong debugging
        # path (Bugbot LOW: "Dual verifier log says CNAME"). Reuse the
        # record_type we already attached to www_domain (set from
        # CnameDnsChecker.expected_cname_target above) instead.
        missing = []
        missing << "apex A record" unless apex_result[:verified]
        missing << "www #{www_record_type} record" unless www_result[:verified]
        Rails.logger.warn "[DualDomainVerifier] ❌ Missing: #{missing.join(', ')}"
      end

      result

    rescue => e
      Rails.logger.error "[DualDomainVerifier] Verification failed: #{e.message}"
      {
        domain: @domain_name,
        overall_verified: false,
        apex_domain: { verified: false, error: e.message },
        www_domain: { verified: false, error: e.message },
        error: e.message,
        checked_at: Time.current
      }
    end
  end

  # Get detailed status for UI display
  # @return [Hash] User-friendly status information
  def status_summary
    result = verify_both_domains
    
    {
      overall_status: result[:overall_verified] ? 'verified' : 'incomplete',
      message: generate_status_message(result),
      apex_status: result[:apex_domain][:verified] ? 'verified' : 'missing',
      www_status: result[:www_domain][:verified] ? 'verified' : 'missing',
      next_steps: generate_next_steps(result)
    }
  end

  private

  # Verify apex domain A record points to the active provider's expected IP.
  # (Render IP on Render, BIZBLASTS_PUBLIC_IP on Caddy.) See Bugbot HIGH:
  # "DNS checks ignore Caddy targets".
  def verify_apex_domain
    Rails.logger.info "[DualDomainVerifier] Checking A record for: #{@apex_domain}"

    resolver = Resolv::DNS.new
    expected_ip = CnameDnsChecker.expected_apex_ip

    begin
      a_records = resolver.getresources(@apex_domain, Resolv::DNS::Resource::IN::A)
      a_ips = a_records.map(&:address).map(&:to_s)

      verified = expected_ip.present? && a_ips.include?(expected_ip)

      {
        verified: verified,
        target: a_ips.first,
        expected_target: expected_ip,
        error: verified ? nil : "A record should point to #{expected_ip}"
      }
    rescue => e
      {
        verified: false,
        target: nil,
        expected_target: expected_ip,
        error: "DNS lookup failed: #{e.message}"
      }
    ensure
      resolver&.close
    end
  end

  # Verify www subdomain record. On Render: expect CNAME → bizblasts.onrender.com.
  # On Caddy: expect A → BIZBLASTS_PUBLIC_IP (CNAME-to-self is also accepted as
  # an alternative, but our recommended docs say A-record for both apex and www).
  def verify_www_domain
    Rails.logger.info "[DualDomainVerifier] Checking www record for: #{@www_domain}"

    expected_cname = CnameDnsChecker.expected_cname_target
    expected_ip    = CnameDnsChecker.expected_apex_ip
    resolver       = Resolv::DNS.new

    begin
      if expected_cname
        cname_records = resolver.getresources(@www_domain, Resolv::DNS::Resource::IN::CNAME)
        if cname_records.empty?
          return {
            verified: false,
            target: nil,
            expected_target: expected_cname,
            error: "No CNAME record found"
          }
        end

        cname_target = cname_records.first.name.to_s.chomp('.')
        verified = cname_target.downcase == expected_cname.downcase

        {
          verified: verified,
          target: cname_target,
          expected_target: expected_cname,
          error: verified ? nil : "CNAME should point to #{expected_cname}"
        }
      else
        # Caddy mode: verify www has an A record pointing to BIZBLASTS_PUBLIC_IP.
        a_records = resolver.getresources(@www_domain, Resolv::DNS::Resource::IN::A)
        a_ips = a_records.map(&:address).map(&:to_s)
        verified = expected_ip.present? && a_ips.include?(expected_ip)

        {
          verified: verified,
          target: a_ips.first,
          expected_target: expected_ip,
          error: verified ? nil : "www A record should point to #{expected_ip}"
        }
      end
    rescue => e
      {
        verified: false,
        target: nil,
        expected_target: expected_cname || expected_ip,
        error: "DNS lookup failed: #{e.message}"
      }
    ensure
      resolver&.close
    end
  end

  # Generate user-friendly status message. The www record type is
  # provider-dependent (CNAME on Render, A on Caddy) so we read it from
  # the verified result rather than hard-coding "CNAME" — otherwise
  # Caddy users see misleading copy in status_summary (Bugbot LOW:
  # "Status messages still say CNAME").
  def generate_status_message(result)
    www_type = result[:www_domain][:record_type] || 'CNAME'

    if result[:overall_verified]
      "Both apex domain and www subdomain are correctly configured"
    elsif result[:apex_domain][:verified] && !result[:www_domain][:verified]
      "Apex domain (A record) verified, www subdomain (#{www_type}) needs configuration"
    elsif !result[:apex_domain][:verified] && result[:www_domain][:verified]
      "www subdomain (#{www_type}) verified, apex domain (A record) needs configuration"
    else
      "Both A record and #{www_type} record need configuration"
    end
  end

  # Generate next steps for incomplete configurations
  def generate_next_steps(result)
    steps = []

    unless result[:apex_domain][:verified]
      steps << "Add A record: @ → #{result[:apex_domain][:expected_target]}"
    end

    unless result[:www_domain][:verified]
      www_type = result[:www_domain][:record_type] || 'CNAME'
      steps << "Add #{www_type} record: www → #{result[:www_domain][:expected_target]}"
    end

    steps.empty? ? ["Domain configuration is complete!"] : steps
  end
end
