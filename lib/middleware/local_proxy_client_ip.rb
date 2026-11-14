# frozen_string_literal: true

module Middleware
  # Restores the visitor IP for the Cloudflare tunnel path.
  #
  # Production is Cloudflare -> cloudflared -> Caddy -> Puma, all on one
  # box, so every request's REMOTE_ADDR is the loopback peer (Caddy).
  # Rack and Rails already trust loopback as a proxy, but Caddy was
  # forwarding 127.0.0.1 in X-Forwarded-For, and neither Rack nor
  # cloudflare-rails reads CF-Connecting-IP unless the socket peer is a
  # Cloudflare address. Every throttle then shared one 127.0.0.1 bucket.
  #
  # When the socket peer is loopback, adopt a public client IP from
  # CF-Connecting-IP, then X-Forwarded-For, then Forwarded, and rewrite
  # those headers so request.ip and request.remote_ip agree. REMOTE_ADDR
  # stays the Caddy peer (an IPv4-mapped loopback is normalized to
  # 127.0.0.1). The custom-domain TLS callback identifies Caddy by it.
  #
  # Any other peer is a direct hit. Spoofable forwarding headers are
  # removed so a client cannot pick their own throttle key.
  #
  # Loopback trust stays off until TRUST_LOOPBACK_CLIENT_IP=true. Caddy
  # must overwrite CF-Connecting-IP from its trusted client IP before
  # that flag is set. deploy.sh restarts Puma and does not edit Caddy,
  # so enabling the flag in the same restart would let a direct Caddy
  # client supply the throttle key. Development and test default the
  # flag on. A process on this box can still connect to Puma directly.
  class LocalProxyClientIp
    SPOOFABLE_HEADERS = %w[
      HTTP_X_FORWARDED_FOR
      HTTP_FORWARDED
      HTTP_CF_CONNECTING_IP
      HTTP_TRUE_CLIENT_IP
      HTTP_X_REAL_IP
      HTTP_CLIENT_IP
    ].freeze

    def initialize(app)
      @app = app
    end

    def self.trust_loopback_client_ip?
      default = Rails.env.local? ? 'true' : 'false'
      ActiveModel::Type::Boolean.new.cast(ENV.fetch('TRUST_LOOPBACK_CLIENT_IP', default))
    end

    def call(env)
      normalize_mapped_loopback!(env)

      if self.class.trust_loopback_client_ip? && loopback_peer?(env['REMOTE_ADDR'])
        # Client-Ip plus X-Forwarded-For makes ActionDispatch::RemoteIp raise.
        env.delete('HTTP_CLIENT_IP')
        ip = resolve_client_ip(env)
        apply_client_ip!(env, ip) if ip
      else
        # Flag off, or a direct hit. Drop the headers so Rack's default
        # loopback trust cannot honor a caller-supplied X-Forwarded-For.
        strip_forwarding_headers!(env)
      end

      @app.call(env)
    end

    private

    def resolve_client_ip(env)
      single_public_ip(env['HTTP_CF_CONNECTING_IP']) ||
        client_from_forwarded_for(env['HTTP_X_FORWARDED_FOR']) ||
        client_from_forwarded_header(env['HTTP_FORWARDED'])
    end

    def apply_client_ip!(env, ip)
      env['HTTP_X_FORWARDED_FOR'] = ip
      env['HTTP_CF_CONNECTING_IP'] = ip
      env['HTTP_FORWARDED'] = forwarded_field(ip)
      env.delete('HTTP_CLIENT_IP')
    end

    def strip_forwarding_headers!(env)
      SPOOFABLE_HEADERS.each { |key| env.delete(key) }
    end

    def single_public_ip(value)
      raw = value.to_s.strip
      return if raw.empty? || raw.include?(',')

      ip = canonical_ip(raw)
      ip unless ip.nil? || proxy_address?(ip)
    end

    def client_from_forwarded_for(header)
      ips = header.to_s.split(',').filter_map { |part| canonical_ip(part) }
      first_untrusted(ips)
    end

    def client_from_forwarded_header(header)
      ips = header.to_s.split(',').filter_map { |part| for_parameter(part) }
      first_untrusted(ips)
    end

    def for_parameter(part)
      match = part.match(/for=("?)(\[[^\]]+\]|[^;,\s"]+)\1/i)
      canonical_ip(match[2]) if match
    end

    def first_untrusted(ips)
      ips.reverse_each do |ip|
        return ip unless proxy_address?(ip)
      end
      nil
    end

    def forwarded_field(ip)
      addr = IPAddr.new(ip)
      addr.ipv6? ? %(for="[#{addr}]") : "for=#{addr}"
    end

    def canonical_ip(token)
      candidate = token.to_s.strip.delete('"')
      candidate = candidate.sub(/\Afor=/i, '')
      candidate = candidate.sub(/\A\[([^\]]+)\](?::\d+)?\z/, '\1')
      candidate = candidate.sub(/\A(\d{1,3}(?:\.\d{1,3}){3}):\d+\z/, '\1')
      addr = IPAddr.new(candidate)
      return unless addr.ipv4? || addr.ipv6?
      return unless addr.to_range.begin == addr.to_range.end

      addr.to_s
    rescue IPAddr::Error
      nil
    end

    # Rack only treats 127.0.0.0/8 and ::1 as loopback proxies. An IPv4-mapped
    # loopback peer (::ffff:127.0.0.1) would otherwise hide X-Forwarded-For.
    def normalize_mapped_loopback!(env)
      ip = IPAddr.new(env['REMOTE_ADDR'].to_s)
      return unless ip.ipv4_mapped? && ip.native.loopback?

      env['REMOTE_ADDR'] = ip.native.to_s
    rescue IPAddr::Error
      nil
    end

    def loopback_peer?(addr)
      ip = IPAddr.new(addr.to_s)
      ip = ip.native if ip.ipv4_mapped?
      ip.loopback?
    rescue IPAddr::Error
      false
    end

    # Same predicate Rack::Attack uses for request.ip, including the
    # Cloudflare ranges cloudflare-rails prepends onto Rack::Request.
    def proxy_address?(ip)
      probe_request.trusted_proxy?(ip.to_s)
    end

    def probe_request
      Rack::Request.new({ 'REMOTE_ADDR' => '127.0.0.1' })
    end
  end
end
