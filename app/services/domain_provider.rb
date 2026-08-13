# frozen_string_literal: true

# Selects the active custom-domain provider implementation.
#
# Behaviour:
#   - If BIZBLASTS_DOMAIN_PROVIDER is set, honor it explicitly
#     ("caddy" or "render"; anything else raises).
#   - Otherwise default to RenderDomainService when RENDER_API_KEY is
#     configured (legacy Render deployment), and CaddyDomainService when
#     it isn't (the Ubuntu/Caddy deployment).
#
# This keeps the migration backwards-compatible: production stays on Render
# until DNS is cut over and RENDER_API_KEY is removed, at which point the
# Ubuntu host transparently switches to CaddyDomainService.
module DomainProvider
  class UnknownProviderError < StandardError; end

  def self.current
    case provider_name
    when 'caddy'  then CaddyDomainService.new
    when 'render' then RenderDomainService.new
    else
      raise UnknownProviderError, "Unknown BIZBLASTS_DOMAIN_PROVIDER=#{provider_name.inspect}"
    end
  end

  def self.provider_name
    explicit = ENV['BIZBLASTS_DOMAIN_PROVIDER'].to_s.strip.downcase
    return explicit if %w[caddy render].include?(explicit)

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

  def self.render?
    provider_name == 'render'
  end
end
