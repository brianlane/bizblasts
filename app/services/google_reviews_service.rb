# frozen_string_literal: true

# GoogleReviewsService handles fetching Google Place reviews
# while maintaining Google Policy compliance:
#
# 1. No filtering or reordering of reviews
# 2. Display most recent reviews as returned by Google
# 3. Proper attribution and linking to Google
# 4. Caching to stay within API quotas
# 5. No storage of review content (only caching)
class GoogleReviewsService
  include ActiveSupport::Benchmarkable
  
  # Google Places API (New) endpoints
  PLACE_DETAILS_V1_URL = 'https://places.googleapis.com/v1/places/'
  
  # Maximum reviews to fetch (Google Policy compliant)
  MAX_REVIEWS = 5
  
  # Cache duration to manage API quota (1 hour)
  CACHE_DURATION = 1.hour
  
  class << self
    # Fetch reviews for a business
    # Returns a hash with rating, reviews, and Google URL
    def fetch(business)
      new(business).fetch
    end
  end
  
  def initialize(business)
    @business = business
    @place_id = business.google_place_id
    @api_key = ENV['GOOGLE_API_KEY']
  end
  
  # Fetch reviews from Google Places API or cache
  def fetch
    return { error: 'Google Place ID not configured' } unless @place_id.present?
    return { error: 'Google API key not configured' } unless @api_key.present?
    
    cache_key = "google_reviews_#{@business.id}_#{@place_id}"
    
    Rails.cache.fetch(cache_key, expires_in: CACHE_DURATION) do
      benchmark "GoogleReviewsService fetch for business #{@business.id}" do
        fetch_from_api_v1
      end
    end
  rescue => e
    Rails.logger.error "[GoogleReviewsService] Error fetching reviews for business #{@business.id}: #{e.message}"
    { error: 'Unable to fetch reviews at this time' }
  end
  
  private
  
  # Fetch reviews from Google Places API (v1)
  def fetch_from_api_v1
    field_mask = [
      'id',
      'displayName',
      'formattedAddress',
      'rating',
      'userRatingCount',
      'googleMapsUri',
      'reviews'
    ].join(',')

    url = PLACE_DETAILS_V1_URL + @place_id
    headers = {
      'X-Goog-Api-Key' => @api_key,
      'X-Goog-FieldMask' => field_mask
    }

    response = make_request_v1(url, headers: headers)
    return { error: 'Failed to fetch reviews' } unless response

    parse_v1_response(response)
  end

  # Make HTTP request to Google Places API v1
  def make_request_v1(url, headers: {})
    require 'net/http'
    require 'uri'
    require 'json'

    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 10
    http.open_timeout = 5

    request = Net::HTTP::Get.new(uri)
    headers.each { |k, v| request[k] = v }

    response = http.request(request)
    if response.code == '200'
      JSON.parse(response.body)
    else
      Rails.logger.error "[GoogleReviewsService] API v1 request failed: #{response.code} - #{response.body}"
      nil
    end
  rescue Timeout::Error, Net::OpenTimeout, Net::ReadTimeout => e
    Rails.logger.error "[GoogleReviewsService] Timeout error: #{e.message}"
    nil
  rescue JSON::ParserError => e
    Rails.logger.error "[GoogleReviewsService] JSON parse error: #{e.message}"
    nil
  rescue => e
    Rails.logger.error "[GoogleReviewsService] Unexpected error: #{e.message}"
    nil
  end
  
  # Parse Google Places API v1 response
  def parse_v1_response(result)
    # v1 returns the place directly, not wrapped under 'result'
    return { error: 'Invalid API response' } unless result.is_a?(Hash)

    place_data = {
      name: result.dig('displayName', 'text') || result['displayName'],
      rating: result['rating'],
      user_ratings_total: result['userRatingCount'],
      google_url: result['googleMapsUri']
    }

    reviews = Array(result['reviews'])
    processed_reviews = reviews.first(MAX_REVIEWS).map do |review|
      process_review_v1(review)
    end

    {
      success: true,
      place: place_data,
      reviews: processed_reviews,
      google_url: generate_google_reviews_url,
      fetched_at: Time.current
    }
  end
  
  # Process individual review (Google Policy compliant)
  # Process individual review from Places API v1
  def process_review_v1(review)
    author = review['authorAttribution'] || review['reviewer'] || {}
    {
      author_name: author['displayName'],
      author_url: author['uri'],
      profile_photo_url: author['photoUri'],
      rating: review['rating'],
      relative_time_description: nil,
      text: review['text'],
      time: begin
        ts = review['publishTime']
        ts ? Time.parse(ts) : nil
      rescue
        nil
      end
    }
  end
  
  # Generate Google Reviews URL for "Write a Review" link
  def generate_google_reviews_url
    "https://search.google.com/local/writereview?placeid=#{@place_id}"
  end
  
  def logger
    Rails.logger
  end
end