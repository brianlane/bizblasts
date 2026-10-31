# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

# Cloudflare for SaaS (Custom Hostnames) provider.
#
# Registers a business's apex and www names on the bizblasts.com zone so
# Cloudflare can terminate TLS and send the request through the fallback
# origin (customers.bizblasts.com) and the tunnel. Caddy on the origin only
# reverse-proxies; it no longer issues customer certificates.
#
# Existing hostnames are looked up by name before create, so a hostname that
# was added by hand (or by an earlier run) is reused instead of duplicated.
#
# Credentials come from CLOUDFLARE_ZONE_ID and CLOUDFLARE_SAAS_API_TOKEN.
# The token is never written to logs.
class CloudflareDomainService
  class CloudflareApiError < StandardError; end
  class DomainNotFoundError < CloudflareApiError; end
  class InvalidCredentialsError < CloudflareApiError; end
  class RateLimitError < CloudflareApiError; end
  class DuplicateHostname < CloudflareApiError; end

  API_BASE = 'https://api.cloudflare.com/client/v4'
  ACTIVE_HOSTNAME_STATUSES = %w[active active_redeploying].freeze
  ACTIVE_SSL_STATUSES = %w[active].freeze

  def initialize
    @zone_id = ENV['CLOUDFLARE_ZONE_ID'].to_s.strip
    @api_token = ENV['CLOUDFLARE_SAAS_API_TOKEN'].to_s.strip

    raise InvalidCredentialsError, 'CLOUDFLARE_ZONE_ID not configured' if @zone_id.blank?
    raise InvalidCredentialsError, 'CLOUDFLARE_SAAS_API_TOKEN not configured' if @api_token.blank?
  end

  # Create a custom hostname, or return the existing one when Cloudflare
  # already has it. ssl method http / type dv matches hostnames that were
  # registered by hand.
  def add_domain(domain_name)
    name = normalize_host(domain_name)
    existing = lookup_hostname(name)
    if existing
      Rails.logger.info "[CloudflareDomainService] custom hostname already present: #{name} id=#{existing['id']}"
      return normalize_domain_data(existing)
    end

    Rails.logger.info "[CloudflareDomainService] creating custom hostname: #{name}"
    data = post('/custom_hostnames', {
      hostname: name,
      ssl: { method: 'http', type: 'dv' }
    })
    normalize_domain_data(data['result'])
  rescue DuplicateHostname
    existing = lookup_hostname(name)
    unless existing
      raise CloudflareApiError, "Duplicate custom hostname #{name} but a follow-up lookup found nothing"
    end

    Rails.logger.info "[CloudflareDomainService] reused custom hostname after duplicate response: #{name} id=#{existing['id']}"
    normalize_domain_data(existing)
  end

  # Read hostname + SSL status. `verified` is true only when Cloudflare
  # reports the hostname active and the edge certificate active.
  def verify_domain(domain_id)
    raw = fetch_by_id(domain_id)
    normalized = normalize_domain_data(raw)
    {
      'verified' => normalized['verified'] == true,
      'queued' => false,
      'domain' => normalized,
      'hostname_status' => normalized['status'],
      'ssl_status' => normalized['ssl_status']
    }
  end

  def list_domains
    page = 1
    rows = []
    loop do
      data = get('/custom_hostnames', page: page, per_page: 50)
      batch = Array(data['result'])
      rows.concat(batch)
      total_pages = data.dig('result_info', 'total_pages').to_i
      break if batch.empty? || total_pages <= page || page >= 20

      page += 1
    end
    rows.map { |row| normalize_domain_data(row) }
  end

  def remove_domain(domain_id)
    id = domain_id.to_s.strip
    raise DomainNotFoundError, 'Missing custom hostname id' if id.blank?

    Rails.logger.info "[CloudflareDomainService] deleting custom hostname id=#{id}"
    delete("/custom_hostnames/#{id}")
    true
  rescue DomainNotFoundError
    Rails.logger.info "[CloudflareDomainService] custom hostname already absent id=#{id}"
    true
  end

  def find_domain_by_name(domain_name)
    raw = lookup_hostname(normalize_host(domain_name))
    raw && normalize_domain_data(raw)
  end

  def find_domain_by_id(domain_id)
    normalize_domain_data(fetch_by_id(domain_id))
  rescue DomainNotFoundError
    nil
  end

  def normalize_domain_data(domain)
    return nil unless domain.is_a?(Hash)

    row = domain.key?('hostname') ? domain : domain['result']
    return nil unless row.is_a?(Hash)

    hostname_status = row['status'].to_s
    ssl_status = row.dig('ssl', 'status').to_s
    verified = ACTIVE_HOSTNAME_STATUSES.include?(hostname_status) && ACTIVE_SSL_STATUSES.include?(ssl_status)

    {
      'id' => row['id'],
      'name' => row['hostname'],
      'verified' => verified,
      'verificationStatus' => verified ? 'verified' : 'unverified',
      'status' => hostname_status,
      'ssl_status' => ssl_status,
      'ownership_verification' => row['ownership_verification'],
      'validation_records' => row.dig('ssl', 'validation_records'),
      'cloudflare' => true
    }
  end

  def domain_status(domain_name)
    domain = find_domain_by_name(domain_name)
    return { exists: false, verified: false, domain_id: nil } if domain.nil?

    {
      exists: true,
      verified: domain['verified'] == true,
      domain_id: domain['id'],
      domain_data: domain,
      hostname_status: domain['status'],
      ssl_status: domain['ssl_status']
    }
  end

  # Apex and www are separate custom hostnames. Monitoring treats the pair
  # as verified only when both are active and both certificates are active.
  def pair_verification(hostname)
    apex = normalize_host(hostname).sub(/\Awww\./, '')
    parts = [apex, "www.#{apex}"].uniq.map { |name| single_verification(name) }
    missing = parts.reject { |part| part[:verified] }.map { |part| part[:name] }

    {
      found: parts.all? { |part| part[:found] },
      verified: parts.all? { |part| part[:verified] },
      hostnames: parts,
      error: missing.empty? ? nil : "Cloudflare hostname or SSL is not active for #{missing.join(', ')}"
    }
  end

  # TXT records Cloudflare returned for pre-validation (ownership or
  # certificate). HTTP DCV does not always include these; callers show
  # them only when present.
  def txt_records_for(hostname)
    apex = normalize_host(hostname).sub(/\Awww\./, '')
    [apex, "www.#{apex}"].uniq.flat_map do |name|
      row = lookup_hostname(name)
      next [] unless row

      self.class.extract_txt_records(row).map { |record| record.merge(hostname: name) }
    end
  end

  def self.extract_txt_records(row)
    return [] unless row.is_a?(Hash)

    records = []
    ownership = row['ownership_verification']
    if ownership.is_a?(Hash) && ownership['type'].to_s.casecmp('txt').zero?
      name = ownership['name'].to_s.strip
      value = ownership['value'].to_s.strip
      records << { name: name, value: value, purpose: 'ownership' } if name.present? && value.present?
    end

    Array(row.dig('ssl', 'validation_records')).each do |record|
      next unless record.is_a?(Hash)

      name = record['txt_name'].to_s.strip
      value = record['txt_value'].to_s.strip
      records << { name: name, value: value, purpose: 'certificate' } if name.present? && value.present?
    end

    records.uniq { |record| [record[:name], record[:value]] }
  end

  private

  def single_verification(name)
    domain = find_domain_by_name(name)
    if domain.nil?
      return { name: name, found: false, verified: false }
    end

    verification = verify_domain(domain['id'])
    {
      name: name,
      found: true,
      verified: verification['verified'] == true,
      domain_id: domain['id'],
      hostname_status: verification['hostname_status'],
      ssl_status: verification['ssl_status']
    }
  end

  def lookup_hostname(name)
    data = get('/custom_hostnames', hostname: name)
    Array(data['result']).find { |row| row.is_a?(Hash) && row['hostname'].to_s.downcase == name }
  end

  def fetch_by_id(domain_id)
    id = domain_id.to_s.strip
    raise DomainNotFoundError, 'Missing custom hostname id' if id.blank?

    data = get("/custom_hostnames/#{id}")
    result = data['result']
    raise DomainNotFoundError, "Custom hostname not found: #{id}" unless result.is_a?(Hash)

    result
  end

  def get(path, query = nil)
    perform(:get, path, query: query)
  end

  def post(path, body)
    perform(:post, path, body: body)
  end

  def delete(path)
    perform(:delete, path)
  end

  def perform(method, path, query: nil, body: nil)
    uri = URI("#{API_BASE}/zones/#{@zone_id}#{path}")
    uri.query = URI.encode_www_form(query) if query.present?

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 20

    request = case method
              when :get then Net::HTTP::Get.new(uri)
              when :post then Net::HTTP::Post.new(uri)
              when :delete then Net::HTTP::Delete.new(uri)
              else
                raise ArgumentError, "Unsupported HTTP method: #{method}"
              end
    request['Authorization'] = "Bearer #{@api_token}"
    request['Content-Type'] = 'application/json'
    request['Accept'] = 'application/json'
    request.body = JSON.generate(body) if body

    response = http.request(request)
    parse_response(response)
  rescue DuplicateHostname, DomainNotFoundError, InvalidCredentialsError, RateLimitError
    raise
  rescue CloudflareApiError
    raise
  rescue StandardError => e
    Rails.logger.error "[CloudflareDomainService] request failed: #{redact(e.message)}"
    raise CloudflareApiError, 'Cloudflare API request failed'
  end

  def parse_response(response)
    code = response.code.to_i
    raw = response.body.to_s
    parsed = raw.strip.empty? ? {} : JSON.parse(raw)
    data = parsed.is_a?(Hash) ? parsed : {}

    raise RateLimitError, 'Cloudflare API rate limit exceeded' if code == 429
    if code == 401 || code == 403
      raise InvalidCredentialsError, 'Cloudflare API rejected the SaaS token'
    end
    raise DomainNotFoundError, 'Custom hostname not found' if code == 404
    raise DuplicateHostname, 'Duplicate custom hostname' if duplicate_response?(data, code)

    unless code.between?(200, 299) && data['success'] != false
      raise CloudflareApiError, "Cloudflare API error (#{code}): #{error_summary(data)}"
    end

    data
  rescue JSON::ParserError
    raise CloudflareApiError, "Cloudflare API returned invalid JSON (HTTP #{response.code})"
  end

  def duplicate_response?(data, code)
    return true if code == 409

    Array(data['errors']).any? do |error|
      error.is_a?(Hash) && (error['code'].to_i == 1406 || error['message'].to_s.match?(/duplicate custom hostname/i))
    end
  end

  def error_summary(data)
    messages = Array(data['errors']).filter_map { |error| error.is_a?(Hash) ? error['message'] : nil }
    redact(messages.presence&.join('; ') || 'unknown error')
  end

  def redact(text)
    secret = @api_token.to_s
    value = text.to_s
    return value if secret.blank?

    value.gsub(secret, '[redacted]')
  end

  def normalize_host(host)
    host.to_s.strip.downcase.chomp('.')
  end
end
