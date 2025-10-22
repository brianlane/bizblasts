# frozen_string_literal: true

# GooglePlacesSearchService handles searching for businesses using Google Places API
# to help business owners easily find and connect their Google Business listing
class GooglePlacesSearchService
  include ActiveSupport::Benchmarkable
  
  # ActiveSupport::Benchmarkable expects the including class to expose a
  # `logger` method. In service objects this is not provided by default,
  # so we forward to the Rails application logger.
  delegate :logger, to: :Rails
  
  # Google Places API (New) endpoints only
  SEARCH_TEXT_URL = 'https://places.googleapis.com/v1/places:searchText'
  SEARCH_NEARBY_URL = 'https://places.googleapis.com/v1/places:searchNearby'
  PLACE_DETAILS_V1_URL = 'https://places.googleapis.com/v1/places/'
  
  class << self
    # Search for businesses by name and location
    def search_businesses(query, location = nil)
      new.search_businesses(query, location)
    end
    
    # Get detailed business information by place_id
    delegate :get_business_details, to: :new
    
    # Search for businesses near specific coordinates
    def search_nearby(latitude, longitude, query = nil, radius_meters = 1000)
      new.search_nearby(latitude, longitude, query, radius_meters)
    end
  end
  
  def initialize
    @api_key = ENV['GOOGLE_API_KEY']
  end
  
  # Search for businesses using Google Places API with smart query optimization
  def search_businesses(query, location = nil)
    return { error: 'Google API key not configured' } unless @api_key.present?
    return { error: 'Search query is required' } if query.blank?
    
    benchmark "GooglePlacesSearchService search for: #{query}" do
      smart_search_with_fallbacks(query, location)
    end
  rescue => e
    Rails.logger.error "[GooglePlacesSearchService] Error searching businesses: #{e.message}"
    Rails.logger.error "[GooglePlacesSearchService] Backtrace: #{e.backtrace.first(5).join(', ')}"
    { error: 'Unable to search for businesses at this time', debug_error: e.message }
  end
  
  # Get detailed information about a specific place
  def get_business_details(place_id)
    return { error: 'Google API key not configured' } unless @api_key.present?
    return { error: 'Place ID is required' } if place_id.blank?
    
    benchmark "GooglePlacesSearchService details for: #{place_id}" do
      fetch_place_details_v1(place_id)
    end
  rescue => e
    Rails.logger.error "[GooglePlacesSearchService] Error fetching business details: #{e.message}"
    { error: 'Unable to fetch business details at this time' }
  end
  
  # Search for businesses near specific coordinates
  def search_nearby(latitude, longitude, query = nil, radius_meters = 1000)
    return { error: 'Google API key not configured' } if @api_key.blank?
    return { error: 'Latitude and longitude are required' } if latitude.blank? || longitude.blank?
    
    benchmark "GooglePlacesSearchService nearby search at: #{latitude}, #{longitude}" do
      search_nearby_with_places_v1(latitude, longitude, query, radius_meters)
    end
  rescue => e
    Rails.logger.error "[GooglePlacesSearchService] Error searching nearby businesses: #{e.message}"
    { error: 'Unable to search for nearby businesses at this time', debug_error: e.message }
  end
  
  private
  
  # Smart search that tries multiple query variations to find the best match
  def smart_search_with_fallbacks(original_query, location)
    # Try different query optimization strategies in order of preference
    queries_to_try = generate_query_variations(original_query, location)
    last_error_message = nil
    
    queries_to_try.each_with_index do |query_info, index|
      Rails.logger.debug do
        "[GooglePlacesSearchService] Trying query #{index + 1}/#{queries_to_try.length}: '#{query_info[:query]}' (#{query_info[:strategy]})"
      end
      
      result = search_with_places_v1(query_info[:query], query_info[:location])
      # Capture any error so we can surface it if no attempts succeed
      if result.is_a?(Hash) && result[:error].present?
        last_error_message = result[:error]
        next
      end
      
      next unless result[:success] && result[:businesses]&.any?

      # Add metadata about which strategy worked
      result[:search_strategy] = query_info[:strategy]
      result[:original_query] = original_query
      return result
    end
    
    # If every attempt failed with an API error, surface the error instead of a success response
    return { error: last_error_message } if last_error_message.present?

    # If no queries returned results and there were no API errors, return a helpful empty-success response
    {
      success: true,
      businesses: [],
      total_results: 0,
      message: generate_helpful_no_results_message(original_query, location),
      queries_tried: queries_to_try.map { |q| q[:query] }
    }
  end
  
  # Generate different query variations to try
  def generate_query_variations(query, location)
    variations = []
    
    # Strategy 1: Original query with location
    if location.present?
      variations << { 
        query: "#{query} #{location}", 
        location: nil, 
        strategy: 'original_with_location' 
      }
    end
    
    # Strategy 2: Original query as-is
    variations << { 
      query: query, 
      location: location, 
      strategy: 'original' 
    }
    
    # Strategy 3: Remove common business suffixes and descriptors
    cleaned_query = clean_business_name(query)
    if cleaned_query != query && cleaned_query.length >= 3
      variations << { 
        query: cleaned_query, 
        location: location, 
        strategy: 'cleaned_name' 
      }
      
      # Also try cleaned query with location
      if location.present?
        variations << { 
          query: "#{cleaned_query} #{location}", 
          location: nil, 
          strategy: 'cleaned_with_location' 
        }
      end
    end
    
    # Strategy 4: Extract just the core business name (first 1-3 words)
    core_name = extract_core_business_name(query)
    if core_name != query && core_name.length >= 3
      variations << { 
        query: core_name, 
        location: location, 
        strategy: 'core_name' 
      }
    end
    
    # Strategy 5: Try business category if query seems too specific
    if query.length > 25 || query.match?(/detail|protection|service|shop|center/i)
      category = extract_business_category(query)
      if category && location.present?
        variations << { 
          query: "#{category} #{location}", 
          location: nil, 
          strategy: 'category_search' 
        }
      end
    end
    
    variations.uniq { |v| v[:query] }
  end
  
  # Clean business name by removing common suffixes and descriptors
  def clean_business_name(name)
    # Limit input length to prevent ReDoS
    return name if name.length > 200

    # Remove common business descriptors and suffixes - simplified patterns to prevent ReDoS
    # Split into simpler, non-backtracking patterns
    cleaned = name.dup

    # Remove "& Protection/Services/etc" or "and Protection/Services/etc" at end
    cleaned = cleaned.sub(/\s+(?:&|and)\s+(?:Protection|Service|Services|Solution|Solutions|Company|Corp|Inc|LLC)\s*\z/i, '')

    # Remove "Detail/Auto/etc & " or "Detail/Auto/etc and " patterns
    cleaned = cleaned.gsub(/\s+(?:Detail|Detailing|Auto|Car|Vehicle)\s+(?:&|and)\s+/i, ' ')

    # Clean up multiple spaces
    cleaned.gsub(/\s{2,}/, ' ').strip
  end

  # Extract the core business name (typically first 1-3 words)
  def extract_core_business_name(name)
    words = name.split(/\s+/)

    # For possessive names like "Joe's" or "Mike's", keep at least 2 words
    # Use simpler pattern to avoid ReDoS
    if words.first && words.first.end_with?("'s") && words.length > 1
      words.first(2).join(' ')
    else
      # Otherwise, take first 1-2 words
      words.first([words.length, 2].min).join(' ')
    end
  end
  
  # Extract business category from detailed name
  def extract_business_category(name)
    categories = {
      /detail|wash|clean/i => 'auto detail',
      /repair|mechanic|automotive/i => 'auto repair', 
      /restaurant|food|cafe/i => 'restaurant',
      /salon|hair|beauty/i => 'beauty salon',
      /dental|dentist/i => 'dentist',
      /medical|doctor|clinic/i => 'medical clinic'
    }
    
    categories.each do |pattern, category|
      return category if name.match?(pattern)
    end
    
    nil
  end
  
  # Generate helpful message when no results found
  def generate_helpful_no_results_message(query, location)
    suggestions = []
    
    suggestions << "Try a shorter business name" if query.length > 20
    
    suggestions << "Search by business category (e.g., 'auto detail')" if query.match?(/detail|protection|service/i)
    
    suggestions << "Add your city or location" if location.blank?
    
    suggestions << "Remove connecting words like '&' or 'and'" if query.include?('&') || query.include?('and')
    
    base_message = "No businesses found matching your search criteria."
    
    if suggestions.any?
      base_message + " Try: #{suggestions.join(', ')}"
    else
      base_message + " Try using just your business name or business category."
    end
  end
  
  # Search using Places API (New) - Text Search
  def search_with_places_v1(query, location)
    field_mask = [
      'places.id',
      'places.displayName',
      'places.formattedAddress',
      'places.primaryType',
      'places.rating',
      'places.userRatingCount'
    ].join(',')

    body = { textQuery: query }
    
    # Add location bias if location is provided to improve local results
    if location.present?
      body[:locationBias] = {
        regionCode: 'US' # Assuming US-based searches for now
        # Note: Could enhance this to use circle or rectangle bias with geocoding
      }
    end

    headers = {
      'Content-Type' => 'application/json',
      'X-Goog-Api-Key' => @api_key,
      'X-Goog-FieldMask' => field_mask
    }

    response = make_request_v1(SEARCH_TEXT_URL, method: :post, headers: headers, body: body.to_json)
    return { error: 'Failed to search businesses' } unless response

    parse_places_v1_search_response(response)
  end

  # Search using Places API (New) - Nearby Search
  def search_nearby_with_places_v1(latitude, longitude, query = nil, radius_meters = 1000)
    field_mask = [
      'places.id',
      'places.displayName',
      'places.formattedAddress',
      'places.primaryType',
      'places.rating',
      'places.userRatingCount'
    ].join(',')

    body = {
      locationRestriction: {
        circle: {
          center: {
            latitude: latitude.to_f,
            longitude: longitude.to_f
          },
          radius: radius_meters.to_f
        }
      },
      maxResultCount: 20
    }
    
    # Add text query if provided for filtering
    if query.present?
      body[:includedTypes] = ['establishment']
      # For nearby search, we'll filter results by name after getting them
    end

    headers = {
      'Content-Type' => 'application/json',
      'X-Goog-Api-Key' => @api_key,
      'X-Goog-FieldMask' => field_mask
    }

    response = make_request_v1(SEARCH_NEARBY_URL, method: :post, headers: headers, body: body.to_json)
    return { error: 'Failed to search nearby businesses' } unless response

    result = parse_places_v1_search_response(response)
    
    # Filter by query if provided
    if query.present? && result[:success] && result[:businesses]
      filtered_businesses = result[:businesses].select do |business|
        business[:name].downcase.include?(query.downcase) ||
        business[:address].to_s.downcase.include?(query.downcase)
      end
      
      result[:businesses] = filtered_businesses
      result[:total_results] = filtered_businesses.length
      result[:search_strategy] = 'nearby_search_filtered'
    elsif result[:success]
      result[:search_strategy] = 'nearby_search'
    end
    
    result
  end

  # Fetch detailed information for a specific place via Places API (New)
  def fetch_place_details_v1(place_id)
    field_mask = %w[
      id
      displayName
      formattedAddress
      nationalPhoneNumber
      websiteUri
      rating
      userRatingCount
      types
      googleMapsUri
    ].join(',')

    url = PLACE_DETAILS_V1_URL + place_id
    headers = {
      'X-Goog-Api-Key' => @api_key,
      'X-Goog-FieldMask' => field_mask
    }

    response = make_request_v1(url, method: :get, headers: headers)
    return { error: 'Failed to fetch business details' } unless response

    parse_places_v1_details_response(response)
  end

  # Removed all legacy (maps.googleapis.com) endpoints and code paths

  # Make HTTP request to Google Places API (New)
  def make_request_v1(url, method:, headers:, body: nil)
    require 'net/http'
    require 'uri'
    require 'json'

    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 10
    http.open_timeout = 5

    request = case method
              when :post
                Net::HTTP::Post.new(uri)
              else
                Net::HTTP::Get.new(uri)
              end
    headers.each { |k, v| request[k] = v }
    request.body = body if body

    response = http.request(request)
    if response.code == '200'
      JSON.parse(response.body)
    else
      Rails.logger.error "[GooglePlacesSearchService] API v1 request failed: #{response.code} - #{response.body}"
      nil
    end
  rescue Timeout::Error, Net::OpenTimeout, Net::ReadTimeout => e
    Rails.logger.error "[GooglePlacesSearchService] Timeout error (v1): #{e.message}"
    nil
  rescue JSON::ParserError => e
    Rails.logger.error "[GooglePlacesSearchService] JSON parse error (v1): #{e.message}"
    nil
  rescue => e
    Rails.logger.error "[GooglePlacesSearchService] Unexpected error (v1): #{e.message}"
    nil
  end
  
  # Parse Places API (New) searchText response
  def parse_places_v1_search_response(response)
    # Handle the case where Google returns an empty response (no results found)
    unless response['places']
      return { 
        success: true, 
        businesses: [], 
        total_results: 0,
        message: 'No businesses found matching your search criteria'
      }
    end

    businesses = response['places'].map do |place|
      {
        place_id: place['id'],
        name: place.dig('displayName', 'text') || place['displayName'] || 'Unknown Business',
        address: place['formattedAddress'],
        types: Array(place['types']) || [],
        matched_substrings: []
      }
    end

    { success: true, businesses: businesses, total_results: businesses.length }
  end
  
  # Parse Places API (New) details response
  def parse_places_v1_details_response(response)
    # v1 returns the place object directly
    result = response

    business_data = {
      place_id: result['id'],
      name: result.dig('displayName', 'text') || result['displayName'],
      address: result['formattedAddress'],
      phone: result['nationalPhoneNumber'],
      website: result['websiteUri'],
      business_status: nil,
      rating: result['rating'],
      total_ratings: result['userRatingCount'],
      google_url: result['googleMapsUri'],
      types: result['types'] || [],
      photos: [],
      recent_reviews: []
    }

    { success: true, business: business_data }
  end
end
