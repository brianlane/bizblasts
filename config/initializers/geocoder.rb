# frozen_string_literal: true

# For US ZIP codes, we use Nominatim (OpenStreetMap) with proper filtering
# to ensure we get US results only. This is:
# - Free (no API key required)
# - Works well for US addresses when properly filtered
# - No rate limits for reasonable usage

return if Rails.env.test?

Geocoder.configure(
  # Geocoding options
  timeout: 5,                 # geocoding service timeout (secs)
  lookup: :nominatim,         # OpenStreetMap Nominatim - free geocoding service
  ip_lookup: :ipinfo_io,      # name of IP address geocoding service (symbol)
  language: :en,              # ISO-639 language code
  use_https: true,            # use HTTPS for lookup requests? (if supported)
  http_proxy: nil,            # HTTP proxy server (user:pass@host:port)
  https_proxy: nil,           # HTTPS proxy server (user:pass@host:port)
  api_key: nil,               # API key for geocoding service
  cache: Rails.cache,         # cache object (must respond to #[], #[]=, and #del)
  cache_prefix: 'geocoder:',  # prefix (string) to use for all cache keys

  # Exceptions that should not be rescued by default
  # (if you want to implement custom error handling);
  # supports SocketError and Timeout::Error
  always_raise: [],

  # Calculation options
  units: :mi,                 # :km for kilometers or :mi for miles
  distances: :linear,         # :linear or :spherical
  
  # HTTP headers
  http_headers: {
    "User-Agent" => "BizBlasts/1.0 (#{ENV['SUPPORT_EMAIL']})"
  }
)

# Configure Nominatim-specific settings
Geocoder.configure(
  nominatim: {
    host: "nominatim.openstreetmap.org",
    email: ENV['SUPPORT_EMAIL'] # Nominatim requires a valid email for identification
  }
)
