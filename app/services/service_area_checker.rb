# frozen_string_literal: true

require 'zip-codes'

# ServiceAreaChecker validates whether a customer's ZIP code falls within
# a business's service radius using geocoding and distance calculations.
#
# Uses a multi-layered approach for maximum accuracy:
# 1. Nominatim structured search (most accurate when available)
# 2. Nominatim text search with US filtering
# 3. Offline ZIP code database (fallback for missing data)
#
# Usage:
#   checker = ServiceAreaChecker.new(business)
#   result = checker.within_radius?("90210", radius_miles: 50)
#
# Returns:
#   - true if within radius
#   - false if outside radius
#   - :invalid_zip if customer ZIP code cannot be geocoded
#   - :no_business_location if business ZIP code is not set or cannot be geocoded
class ServiceAreaChecker
  DEFAULT_RADIUS_MILES = 50
  GEOCODING_TIMEOUT_SECONDS = 5

  attr_reader :business

  def initialize(business)
    @business = business
  end

  # Checks if a customer's ZIP code is within the specified radius of the business location
  #
  # @param zip_code [String] Customer's ZIP code
  # @param radius_miles [Integer] Service radius in miles (default: 50)
  # @return [Boolean, Symbol] true/false for within/outside radius, or :invalid_zip/:no_business_location for errors
  def within_radius?(zip_code, radius_miles: DEFAULT_RADIUS_MILES)
    # Validate inputs
    return :no_business_location if business.nil? || business.zip.blank?
    return :invalid_zip if zip_code.blank?

    # Get coordinates for both locations
    business_coords = center_coordinates
    return :no_business_location if business_coords.blank?

    customer_coords = coordinates_for(zip_code)
    return :invalid_zip if customer_coords.blank?

    # Calculate distance and compare to radius
    distance = Geocoder::Calculations.distance_between(
      business_coords,
      customer_coords,
      units: :mi
    )

    Rails.logger.info "[ServiceAreaChecker] Distance from #{business.zip} to #{zip_code}: #{distance.round(2)} miles (radius: #{radius_miles} miles)"

    distance <= radius_miles.to_f
  rescue Geocoder::OverQueryLimitError => e
    Rails.logger.error "[ServiceAreaChecker] Geocoding rate limit exceeded for business #{business.id}: #{e.message}"
    # Return true to allow booking when geocoding service is unavailable
    true
  rescue StandardError => e
    Rails.logger.error "[ServiceAreaChecker] Error checking radius for business #{business.id}: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    # Return true to allow booking when there's an error (fail open)
    true
  end

  # Returns the business's coordinates, cached after first lookup
  def center_coordinates
    @center_coordinates ||= coordinates_for(business.zip)
  end

  # Clears the cached business coordinates (useful for testing or if business location changes)
  def clear_cache!
    @center_coordinates = nil
  end

  private

  # Geocodes a ZIP code and returns [latitude, longitude] coordinates
  #
  # @param zip [String] ZIP code to geocode
  # @return [Array<Float>, nil] [latitude, longitude] or nil if geocoding fails
  def coordinates_for(zip)
    return nil if zip.blank?

    # Normalize ZIP code (remove spaces, handle ZIP+4 format)
    normalized_zip = zip.to_s.strip.split('-').first

    # Use Rails cache to avoid repeated API calls for the same ZIP
    cache_key = "geocoder:zip:#{normalized_zip}"
    
    # Check if the key exists in cache (even if the value is nil)
    if Rails.cache.exist?(cache_key)
      return Rails.cache.read(cache_key)
    end

    # Use Nominatim's structured search for better accuracy with US ZIP codes
    # This approach is more reliable than free-form text search
    results = geocode_with_structured_search(normalized_zip)
    result = results.first if results.any?
    
    # If structured search fails, try offline database fallback first
    # This is more accurate than text search for many ZIP codes
    if result.nil?
      Rails.logger.info "[ServiceAreaChecker] Structured search failed for #{normalized_zip}, trying offline database"
      coords = coordinates_from_offline_database(normalized_zip)
      
      if coords.present?
        # Cache successful offline lookups for 30 days
        Rails.cache.write(cache_key, coords, expires_in: 30.days)
        return coords
      end
      
      # If offline database also fails, fall back to text search
      Rails.logger.info "[ServiceAreaChecker] Offline database failed for #{normalized_zip}, trying text search"
      results = Geocoder.search("#{normalized_zip}, USA")
      
      # Filter results to only include US locations
      us_result = results.find { |r| r.respond_to?(:country_code) && r.country_code.to_s.downcase == "us" }
      result = us_result || results.first
    end

    if result && result.coordinates.present?
      coords = result.coordinates
      # Cache successful lookups for 30 days
      Rails.cache.write(cache_key, coords, expires_in: 30.days)
      coords
    else
      Rails.logger.warn "[ServiceAreaChecker] No coordinates found for ZIP: #{normalized_zip}"
      # Cache failed lookups for 1 day to avoid repeated failed attempts
      Rails.cache.write(cache_key, nil, expires_in: 1.day)
      nil
    end
  rescue Timeout::Error => e
    Rails.logger.error "[ServiceAreaChecker] Geocoding timeout for ZIP #{normalized_zip}: #{e.message}"
    nil
  rescue StandardError => e
    Rails.logger.error "[ServiceAreaChecker] Error geocoding ZIP #{normalized_zip}: #{e.class} - #{e.message}"
    nil
  end

  # Performs a structured search using Nominatim's API for better ZIP code accuracy
  def geocode_with_structured_search(zip)
    # Build structured query URL for Nominatim
    # Using structured search is more accurate than free-form text search for ZIP codes
    base_url = "https://nominatim.openstreetmap.org/search"
    params = {
      postalcode: zip,
      country: "United States",
      format: "json",
      addressdetails: 1,
      limit: 1
    }
    
    url = "#{base_url}?#{URI.encode_www_form(params)}"
    
    # Make HTTP request with proper headers
    response = Net::HTTP.start(URI.parse(url).host, 443, use_ssl: true) do |http|
      request = Net::HTTP::Get.new(URI.parse(url))
      request["User-Agent"] = "BizBlasts/1.0 (#{ENV['SUPPORT_EMAIL']})"
      http.request(request)
    end
    
    if response.code == "200"
      data = JSON.parse(response.body)
      # Convert to Geocoder::Result format
      data.map do |item|
        # Create a simple result object that responds to coordinates
        OpenStruct.new(
          coordinates: [item["lat"].to_f, item["lon"].to_f],
          latitude: item["lat"].to_f,
          longitude: item["lon"].to_f,
          country_code: "us",
          display_name: item["display_name"]
        )
      end
    else
      []
    end
  rescue StandardError => e
    Rails.logger.error "[ServiceAreaChecker] Structured search error: #{e.class} - #{e.message}"
    []
  end

  # Gets coordinates from the offline ZIP code database
  # This is used as a final fallback when online geocoding services fail
  # Uses the zip-codes gem to get city/state, then geocodes that with Nominatim
  def coordinates_from_offline_database(zip)
    zip_info = ZipCodes.identify(zip)
    
    if zip_info && zip_info[:city] && zip_info[:state_code]
      # Use city and state to geocode with Nominatim
      city_state_query = "#{zip_info[:city]}, #{zip_info[:state_code]}, USA"
      Rails.logger.info "[ServiceAreaChecker] Trying city/state geocoding: #{city_state_query}"
      
      results = Geocoder.search(city_state_query)
      if results.any?
        result = results.first
        if result.coordinates.present?
          return result.coordinates
        end
      end
    end
    
    nil
  rescue StandardError => e
    Rails.logger.error "[ServiceAreaChecker] Offline database error: #{e.class} - #{e.message}"
    nil
  end
end

