# frozen_string_literal: true

# Verifies that a selected Google place belongs to the current business
class GoogleBusinessVerificationService
  DEFAULT_NAME_STOPWORDS = %w[llc inc co company corp corporation ltd limited the and &].freeze
  US_STATE_ABBR = {
    'alabama' => 'al', 'alaska' => 'ak', 'arizona' => 'az', 'arkansas' => 'ar', 'california' => 'ca',
    'colorado' => 'co', 'connecticut' => 'ct', 'delaware' => 'de', 'florida' => 'fl', 'georgia' => 'ga',
    'hawaii' => 'hi', 'idaho' => 'id', 'illinois' => 'il', 'indiana' => 'in', 'iowa' => 'ia',
    'kansas' => 'ks', 'kentucky' => 'ky', 'louisiana' => 'la', 'maine' => 'me', 'maryland' => 'md',
    'massachusetts' => 'ma', 'michigan' => 'mi', 'minnesota' => 'mn', 'mississippi' => 'ms', 'missouri' => 'mo',
    'montana' => 'mt', 'nebraska' => 'ne', 'nevada' => 'nv', 'new hampshire' => 'nh', 'new jersey' => 'nj',
    'new mexico' => 'nm', 'new york' => 'ny', 'north carolina' => 'nc', 'north dakota' => 'nd', 'ohio' => 'oh',
    'oklahoma' => 'ok', 'oregon' => 'or', 'pennsylvania' => 'pa', 'rhode island' => 'ri', 'south carolina' => 'sc',
    'south dakota' => 'sd', 'tennessee' => 'tn', 'texas' => 'tx', 'utah' => 'ut', 'vermont' => 'vt',
    'virginia' => 'va', 'washington' => 'wa', 'west virginia' => 'wv', 'wisconsin' => 'wi', 'wyoming' => 'wy'
  }.freeze

  def self.verify_match(business, place_hash)
    new(business, place_hash).verify_match
  end

  def initialize(business, place_hash)
    @business = business
    # Normalize keys for reliable access (supports symbol or string keys)
    @place = (place_hash || {}).is_a?(Hash) ? place_hash.with_indifferent_access : {}
  end

  def verify_match
    return allow_result('Verification disabled') if verification_disabled?

    failures = []

    # Compare city/state when address is available
    city_state_ok = compare_city_state
    failures << 'Business city/state do not match Google listing' unless city_state_ok

    # Compare phone if present
    phone_ok = compare_phone
    failures << 'Business phone number does not match Google listing' unless phone_ok

    # Compare name tokens
    name_ok = compare_name
    failures << 'Business name appears different from Google listing' unless name_ok

    # Compare website/domain if present
    website_ok = compare_website
    failures << 'Business website/domain differs from Google listing' unless website_ok

    if failures.empty?
      { ok: true }
    else
      # In development, include detailed mismatch reasons to help debugging
      return { ok: false, errors: failures } if Rails.env.development?
      { ok: false }
    end
  end

  private

  def verification_disabled?
    ENV['GOOGLE_BUSINESS_REQUIRE_STRICT_MATCH']&.strip == 'false'
  end

  def allow_result(message)
    { ok: true, note: message }
  end

  def compare_city_state
    address = @place['address'] || @place['formatted_address']
    return true if address.blank? # cannot compare, do not block

    city = @business.city.to_s.downcase.strip
    state_raw = @business.state.to_s.downcase.strip
    addr_down = address.downcase

    return true if city.blank? || state_raw.blank?

    # Accept either full name or two-letter abbreviation in the address
    state_abbr = if state_raw.length == 2
      state_raw
    else
      US_STATE_ABBR[state_raw]
    end
    state_full = US_STATE_ABBR.key(state_raw) || state_raw

    city_match = addr_down.include?(city)
    state_match = [state_raw, state_abbr, state_full].compact.any? { |s| addr_down.include?(s) }

    city_match && state_match
  end

  def compare_phone
    phone_biz = digits(@business.phone)
    phone_google = digits(@place['phone'] || @place['formatted_phone_number'] || @place['nationalPhoneNumber'])
    return true if phone_biz.blank? || phone_google.blank?

    # Compare last 7 digits to allow for country/area code formatting differences
    phone_biz[-7, 7] == phone_google[-7, 7]
  end

  def compare_name
    biz_tokens = normalize_name(@business.name)
    google_name = @place['name'] || @place.dig('displayName', 'text')
    return false if google_name.blank?
    place_tokens = normalize_name(google_name)

    return true if place_tokens.empty? || biz_tokens.empty?

    overlap = (biz_tokens & place_tokens).length
    # Require only 50% token overlap of the shorter name (rounded up), minimum 1
    min_required = [1, (0.5 * [biz_tokens.length, place_tokens.length].min).ceil].max
    overlap >= min_required
  end

  def compare_website
    site = extract_host(@place['website'] || @place['websiteUri'])
    return true if site.blank? # do not block if missing in Google

    # Only enforce website match if the business has an explicit website/url field
    biz_website = if @business.respond_to?(:website) && @business.website.present?
      @business.website
    elsif @business.respond_to?(:url) && @business.url.present?
      @business.url
    else
      nil
    end

    return true if biz_website.blank? # skip if tenant hasn't set a public website

    biz_host = extract_host(biz_website)
    site.include?(biz_host) || biz_host.include?(site)
  end

  def normalize_name(text)
    text.to_s.downcase.gsub(/[^a-z0-9\s]/, ' ').split.reject { |t| DEFAULT_NAME_STOPWORDS.include?(t) }
  end

  def digits(text)
    text.to_s.gsub(/\D/, '')
  end

  def extract_host(url_or_host)
    raw = url_or_host.to_s.strip
    return '' if raw.blank?
    raw = "https://#{raw}" unless raw.include?('://')
    URI(raw).host.to_s.sub(/^www\./, '')
  rescue
    raw.sub(/^www\./, '')
  end
end

