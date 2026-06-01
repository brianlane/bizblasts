# frozen_string_literal: true

require 'resolv'

# Drop-in replacement for RenderDomainService when the app is hosted behind
# Caddy with on-demand TLS (and a wildcard cert for *.bizblasts.com via the
# Cloudflare DNS plugin).
#
# Unlike Render, Caddy does not require us to pre-register a domain through an
# API: the moment a request arrives for a hostname that AllowedHostService
# approves, Caddy auto-provisions a Let's Encrypt certificate via HTTP-01.
# This service therefore mostly maintains the existing Business record state
# (so the rest of the app — CnameSetupService, DomainMonitoringService,
# DomainMailer, etc. — continues to work unchanged) and verifies DNS by
# comparing the customer's A record to the BizBlasts public IP.
#
# The public interface deliberately mirrors RenderDomainService so callers can
# treat the two interchangeably.
class CaddyDomainService
  class CaddyDomainError < StandardError; end
  class DomainNotFoundError < CaddyDomainError; end
  class InvalidCredentialsError < CaddyDomainError; end
  class RateLimitError < CaddyDomainError; end

  def initialize
    # No remote API to authenticate against — Caddy issues certs locally.
  end

  # "Add" a domain. With Caddy this is a no-op at the infrastructure level;
  # the on_demand_tls verify endpoint will start approving this hostname as
  # soon as the corresponding Business row is in an active state. We return a
  # shape that mimics RenderDomainService so callers don't have to branch.
  def add_domain(domain_name)
    name = normalize(domain_name)
    Rails.logger.info "[CaddyDomainService] add_domain noop: #{name}"
    { 'id' => "caddy:#{name}", 'name' => name, 'verified' => false, 'caddy' => true }
  end

  # "Verify" a domain by DNS-resolving it and comparing to our public IP.
  # Caddy will only complete the TLS handshake once Let's Encrypt issues the
  # cert (a few seconds after first valid request) — this method tells the
  # monitoring code whether the customer's DNS is actually pointing at us yet.
  def verify_domain(domain_id)
    name = id_to_name(domain_id)
    raise DomainNotFoundError, "Unknown domain id: #{domain_id}" if name.blank?

    verified = dns_points_at_us?(name)
    Rails.logger.info "[CaddyDomainService] verify #{name} -> #{verified}"

    {
      'verified' => verified,
      'queued' => false,
      'domain' => { 'id' => domain_id, 'name' => name, 'verificationStatus' => verified ? 'verified' : 'unverified' }
    }
  end

  # All managed custom domains are tracked in the Business table. Return a
  # Render-compatible payload so callers (e.g. find_domain_by_name) keep working.
  #
  # Three important behaviors here:
  #
  # 1. We only include businesses that have actually completed the
  #    CnameSetupService.add_domain step (render_domain_added=true). Otherwise
  #    find_domain_by_name would return a hit for any custom-domain Business
  #    row, including ones still in cname_pending — which is the opposite of
  #    Render's behavior (Render lists only registered domains) and lets
  #    DomainMonitoringService report render_check.found=true before setup
  #    has run (Bugbot MEDIUM: "Caddy lists unregistered hostnames").
  #
  # 2. We emit BOTH the apex (`example.com`) and www (`www.example.com`)
  #    variants for every persisted hostname, regardless of which one the
  #    business stored. Monitoring looks up the *canonical* domain — which
  #    may be the opposite of the stored hostname when canonical_preference
  #    flips — and a missing entry would otherwise cause find_domain_by_name
  #    to return nil and verification to stall indefinitely (Bugbot HIGH:
  #    WWW canonical domain lookup fails).
  #
  # 3. We deliberately set `'verified' => false`. RenderDomainVerificationJob
  #    exits early when `verified` is true, so if we claimed pre-verified
  #    status here the job would never actually call `verify_domain` to do
  #    the live DNS check (Bugbot MEDIUM: Async verify skips DNS check).
  #    Real verification state is computed lazily by verify_domain /
  #    domain_status when callers need it.
  def list_domains
    return [] unless business_table_exists?

    Business.where(host_type: 'custom_domain', render_domain_added: true)
            .where.not(hostname: [nil, ''])
            .pluck(:hostname)
            .flat_map do |hostname|
              apex = normalize(hostname).sub(/\Awww\./, '')
              [apex, "www.#{apex}"].uniq.map do |name|
                { 'id' => "caddy:#{name}", 'name' => name, 'verified' => false }
              end
            end
  end

  # Removing a domain is a no-op: as soon as the Business row transitions
  # away from cname_active, AllowedHostService stops approving it and Caddy
  # will refuse to serve TLS for it. The cert eventually expires and is
  # garbage-collected by Caddy's storage layer.
  def remove_domain(_domain_id)
    Rails.logger.info "[CaddyDomainService] remove_domain noop"
    true
  end

  def find_domain_by_name(domain_name)
    name = normalize(domain_name)
    list_domains.find { |d| d['name'] == name }
  end

  def find_domain_by_id(domain_id)
    name = id_to_name(domain_id)
    list_domains.find { |d| d['name'] == name }
  end

  def normalize_domain_data(domain)
    return nil unless domain.is_a?(Hash)
    domain.key?('name') ? domain : domain['customDomain']
  end

  def domain_status(domain_name)
    name = normalize(domain_name)
    domain = find_domain_by_name(name)
    return { exists: false, verified: false, domain_id: nil } if domain.nil?

    {
      exists: true,
      verified: dns_points_at_us?(name),
      domain_id: domain['id'],
      domain_data: domain
    }
  end

  private

  def normalize(host)
    host.to_s.strip.downcase
  end

  def id_to_name(id)
    id.to_s.sub(/\Acaddy:/, '')
  end

  def business_table_exists?
    ActiveRecord::Base.connection.table_exists?('businesses')
  rescue ActiveRecord::NoDatabaseError
    false
  end

  # Resolve the customer's domain and compare against our public IP. We
  # accept either a configured BIZBLASTS_PUBLIC_IP env var (preferred — set
  # by the cloudflare-ddns updater) or fall back to whatever bizblasts.com
  # itself resolves to (since both records must point at the same host).
  #
  # We deliberately check ONLY the exact hostname passed in. An earlier
  # implementation also looked up the apex and the www-of-apex as siblings,
  # which meant `dns_points_at_us?('www.example.com')` would return true
  # whenever ONLY the apex was correctly pointed at us — leading
  # CnameDnsChecker / monitoring to mark www as verified while Caddy's
  # on_demand_tls would then refuse to mint a cert for it (Bugbot MEDIUM:
  # "Caddy verify accepts sibling DNS"). Strict per-name verification
  # matches what AllowedHostService and Let's Encrypt actually enforce.
  def dns_points_at_us?(name)
    target_ips = our_public_ips
    return false if target_ips.empty?

    resolve_a(name).any? { |ip| target_ips.include?(ip) }
  rescue StandardError => e
    Rails.logger.warn "[CaddyDomainService] DNS check failed for #{name}: #{e.message}"
    false
  end

  # Source of truth for "the IP customers must point their DNS at". We
  # deliberately use the SAME single value that CnameDnsChecker uses for
  # its apex A-record assertion (ENV['BIZBLASTS_PUBLIC_IP'], else the
  # first bizblasts.com A record). Otherwise the two checkers could
  # disagree — provider verify would accept any of the multiple
  # bizblasts.com A records while CnameDnsChecker would only accept the
  # first one — and a customer pointed at a "non-primary" IP would
  # show verified here but stuck in monitoring (Bugbot MEDIUM: "DNS
  # checks disagree on IPs").
  def our_public_ips
    expected = CnameDnsChecker.expected_apex_ip
    expected.present? ? [expected.to_s.strip] : []
  end

  def resolve_a(host)
    Resolv::DNS.open do |r|
      r.getresources(host, Resolv::DNS::Resource::IN::A).map { |a| a.address.to_s }
    end
  rescue StandardError
    []
  end
end
