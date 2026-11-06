# frozen_string_literal: true

# Selects the active custom-domain provider implementation.
#
# Behaviour:
#   - If BIZBLASTS_DOMAIN_PROVIDER is set, honor it explicitly
#     ("cloudflare", "caddy", or "render"; anything else raises).
#   - Otherwise default to CaddyDomainService. Production on the home
#     server sets BIZBLASTS_DOMAIN_PROVIDER=cloudflare so customer domains
#     are Cloudflare for SaaS custom hostnames. Leave the variable unset
#     (or set it to caddy) to keep the previous on-demand TLS behavior.
module DomainProvider
  class UnknownProviderError < StandardError; end

  def self.current
    case provider_name
    when 'cloudflare' then CloudflareDomainService.new
    when 'caddy'      then CaddyDomainService.new
    when 'render'     then RenderDomainService.new
    else
      raise UnknownProviderError, "Unknown BIZBLASTS_DOMAIN_PROVIDER=#{provider_name.inspect}"
    end
  end

  def self.provider_name
    explicit = ENV['BIZBLASTS_DOMAIN_PROVIDER'].to_s.strip.downcase
    return explicit if %w[cloudflare caddy render].include?(explicit)

    # No explicit BIZBLASTS_DOMAIN_PROVIDER set. Default to 'caddy'.
    #
    # This used to default to 'render' so that a legacy Render deployment with a
    # missing or mistyped RENDER_API_KEY would fail loudly against the Render API
    # rather than silently no-op into CaddyDomainService (Bugbot HIGH). BizBlasts
    # is self-hosted on Ubuntu/Caddy now, so there is no Render deployment left
    # for that to protect, and a 'render' default has the failure mode backwards:
    # forget the variable on the Caddy host and custom-domain provisioning silently
    # calls a hosting provider we no longer use.
    #
    # A Render deployment must now set BIZBLASTS_DOMAIN_PROVIDER=render explicitly.
    'caddy'
  end

  def self.caddy?
    provider_name == 'caddy'
  end

  def self.cloudflare?
    provider_name == 'cloudflare'
  end

  def self.render?
    provider_name == 'render'
  end

  # Caddy and Cloudflare both require the apex and the www name to be
  # checked on their own. Render still uses the legacy single-host gate.
  def self.dual_dns?
    caddy? || cloudflare?
  end
end
