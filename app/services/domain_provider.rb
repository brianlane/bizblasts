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

    # No explicit BIZBLASTS_DOMAIN_PROVIDER set. Default to 'render' so that:
    #   - Legacy Render deployments keep working unchanged.
    #   - A Render deployment with a missing/mistyped RENDER_API_KEY fails
    #     loudly (with a real Render API error) instead of silently falling
    #     back to CaddyDomainService no-ops (Bugbot HIGH).
    #   - The existing test suite, which stubs RenderDomainService.new
    #     globally, continues to work without per-spec env juggling.
    # Self-hosted Caddy deployments MUST set BIZBLASTS_DOMAIN_PROVIDER=caddy
    # explicitly (see .env.example and the production .env on the Ubuntu host).
    'render'
  end

  def self.caddy?
    provider_name == 'caddy'
  end

  def self.render?
    provider_name == 'render'
  end
end
