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

    ENV['RENDER_API_KEY'].to_s.strip.empty? ? 'caddy' : 'render'
  end

  def self.caddy?
    provider_name == 'caddy'
  end

  def self.render?
    provider_name == 'render'
  end
end
