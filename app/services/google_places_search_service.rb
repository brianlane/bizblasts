# frozen_string_literal: true

# GooglePlacesSearchService handles searching for businesses using Google Places API
# to help business owners easily find and connect their Google Business listing
class GooglePlacesSearchService
  include ActiveSupport::Benchmarkable
  
  # ActiveSupport::Benchmarkable expects the including class to expose a
  # `logger` method. In service objects this is not provided by default,
  # so we forward to the Rails application logger.
  def logger
    Rails.logger
  end
  
  # Google Places API (New) endpoints only
  SEARCH_TEXT_URL = 'https://places.googleapis.com/v1/places:searchText'
  PLACE_DETAILS_V1_URL = 'https://places.googleapis.com/v1/places/'
  
  class << self
    # Search for businesses by name and location
    def search_businesses(query, location = nil)
      new.search_businesses(query, location)
    end
    
    # Get detailed business information by place_id
    def get_business_details(place_id)
      new.get_business_details(place_id)
    end
  end
  
  def initialize
    @api_key = ENV['GOOGLE_API_KEY']
  end
  
  # Search for businesses using Google Places API
  def search_businesses(query, location = nil)
    return { error: 'Google API key not configured' } unless @api_key.present?
    return { error: 'Search query is required' } if query.blank?
    
    benchmark "GooglePlacesSearchService search for: #{query}" do
      search_with_places_v1(query, location)
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
  
  private
  
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
    # Note: We could add a location bias here if we geocode the provided string.

    headers = {
      'Content-Type' => 'application/json',
      'X-Goog-Api-Key' => @api_key,
      'X-Goog-FieldMask' => field_mask
    }

    response = make_request_v1(SEARCH_TEXT_URL, method: :post, headers: headers, body: body.to_json)
    return { error: 'Failed to search businesses' } unless response

    parse_places_v1_search_response(response)
  end

  # Fetch detailed information for a specific place via Places API (New)
  def fetch_place_details_v1(place_id)
    field_mask = [
      'id',
      'displayName',
      'formattedAddress',
      'nationalPhoneNumber',
      'websiteUri',
      'rating',
      'userRatingCount',
      'types',
      'googleMapsUri'
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
     return { error: 'Invalid search response' } unless response['places']

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