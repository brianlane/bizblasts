# frozen_string_literal: true

# Service for verifying both apex domain (A record) and www subdomain (CNAME record)
# This provides comprehensive domain ownership verification for custom domains
class DualDomainVerifier
  def initialize(domain_name)
    @domain_name = domain_name.to_s.strip.downcase
    @apex_domain = @domain_name.start_with?('www.') ? @domain_name.sub('www.', '') : @domain_name
    @www_domain = @apex_domain.start_with?('www.') ? @apex_domain : "www.#{@apex_domain}"
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
          record_type: 'CNAME',
          target: www_result[:target],
          expected_target: www_result[:expected_target],
          error: www_result[:error]
        },
        checked_at: Time.current
      }

      if overall_verified
        Rails.logger.info "[DualDomainVerifier] ✅ Both domains verified successfully"
      else
        missing = []
        missing << "apex A record" unless apex_result[:verified]
        missing << "www CNAME record" unless www_result[:verified]
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

  # Verify apex domain A record points to Render IP
  def verify_apex_domain
    Rails.logger.info "[DualDomainVerifier] Checking A record for: #{@apex_domain}"
    
    resolver = Resolv::DNS.new
    
    begin
      a_records = resolver.getresources(@apex_domain, Resolv::DNS::Resource::IN::A)
      a_ips = a_records.map(&:address).map(&:to_s)
      
      render_ip = CnameDnsChecker::RENDER_APEX_IP
      verified = a_ips.include?(render_ip)
      
      {
        verified: verified,
        target: a_ips.first,
        expected_target: render_ip,
        error: verified ? nil : "A record should point to #{render_ip}"
      }
    rescue => e
      {
        verified: false,
        target: nil,
        expected_target: CnameDnsChecker::RENDER_APEX_IP,
        error: "DNS lookup failed: #{e.message}"
      }
    ensure
      resolver&.close
    end
  end

  # Verify www subdomain CNAME record points to Render target
  def verify_www_domain
    Rails.logger.info "[DualDomainVerifier] Checking CNAME record for: #{@www_domain}"
    
    resolver = Resolv::DNS.new
    
    begin
      cname_records = resolver.getresources(@www_domain, Resolv::DNS::Resource::IN::CNAME)
      
      if cname_records.empty?
        return {
          verified: false,
          target: nil,
          expected_target: CnameDnsChecker::RENDER_CNAME_TARGET,
          error: "No CNAME record found"
        }
      end
      
      cname_target = cname_records.first.name.to_s.chomp('.')
      render_target = CnameDnsChecker::RENDER_CNAME_TARGET
      verified = cname_target.downcase == render_target.downcase
      
      {
        verified: verified,
        target: cname_target,
        expected_target: render_target,
        error: verified ? nil : "CNAME should point to #{render_target}"
      }
    rescue => e
      {
        verified: false,
        target: nil,
        expected_target: CnameDnsChecker::RENDER_CNAME_TARGET,
        error: "DNS lookup failed: #{e.message}"
      }
    ensure
      resolver&.close
    end
  end

  # Generate user-friendly status message
  def generate_status_message(result)
    if result[:overall_verified]
      "Both apex domain and www subdomain are correctly configured"
    elsif result[:apex_domain][:verified] && !result[:www_domain][:verified]
      "Apex domain (A record) verified, www subdomain (CNAME) needs configuration"
    elsif !result[:apex_domain][:verified] && result[:www_domain][:verified]
      "www subdomain (CNAME) verified, apex domain (A record) needs configuration"
    else
      "Both A record and CNAME record need configuration"
    end
  end

  # Generate next steps for incomplete configurations
  def generate_next_steps(result)
    steps = []
    
    unless result[:apex_domain][:verified]
      steps << "Add A record: @ → #{result[:apex_domain][:expected_target]}"
    end
    
    unless result[:www_domain][:verified]
      steps << "Add CNAME record: www → #{result[:www_domain][:expected_target]}"
    end
    
    steps.empty? ? ["Domain configuration is complete!"] : steps
  end
end
