# GoogleBusinessProfileService handles OAuth and API interactions with Google Business Profile API
# Used for service businesses that may not be discoverable through standard Places API
class GoogleBusinessProfileService
  include ActiveSupport::Benchmarkable
  
  # ActiveSupport::Benchmarkable expects the including class to expose a
  # `logger` method. In service objects this is not provided by default,
  # so we forward to the Rails application logger.
  delegate :logger, to: :Rails
  
  # Google Business Profile API endpoints
  TOKEN_URL = 'https://oauth2.googleapis.com/token'
  ACCOUNTS_URL = 'https://mybusinessaccountmanagement.googleapis.com/v1/accounts'
  LOCATIONS_URL = 'https://mybusinessbusinessinformation.googleapis.com/v1'
  
  class << self
    # Exchange OAuth code for tokens and fetch business accounts
    def exchange_code_and_fetch_profiles(code, redirect_uri)
      new.exchange_code_and_fetch_profiles(code, redirect_uri)
    end
    
    # Get business locations for an account
    def get_business_locations(access_token, account_id)
      new.get_business_locations(access_token, account_id)
    end
  end
  
  def initialize
    # Use unified Google OAuth credentials (shared with Calendar integration)
    credentials = GoogleOauthCredentials.credentials
    @client_id = credentials[:client_id]
    @client_secret = credentials[:client_secret]
  end
  
  # Exchange OAuth code for access tokens and fetch business profiles
  def exchange_code_and_fetch_profiles(code, redirect_uri)
    return { error: 'Google OAuth not configured' } unless @client_id.present? && @client_secret.present?
    
    benchmark "GoogleBusinessProfileService token exchange" do
      # Step 1: Exchange code for tokens
      token_result = exchange_code_for_tokens(code, redirect_uri)
      return token_result unless token_result[:success]
      
      access_token = token_result[:access_token]
      
      # Step 2: Fetch business accounts
      accounts_result = fetch_business_accounts(access_token)
      return accounts_result unless accounts_result[:success]
      
      {
        success: true,
        tokens: {
          access_token: access_token,
          refresh_token: token_result[:refresh_token],
          expires_at: token_result[:expires_at]
        },
        accounts: accounts_result[:accounts]
      }
    end
  rescue => e
    Rails.logger.error "[GoogleBusinessProfileService] Error in exchange_code_and_fetch_profiles: #{e.message}"
    { error: 'Failed to connect to Google Business Profile' }
  end
  
  # Get business locations for a specific account
  def get_business_locations(access_token, account_id)
    return { error: 'Access token is required' } if access_token.blank?
    return { error: 'Account ID is required' } if account_id.blank?
    
    benchmark "GoogleBusinessProfileService fetch locations for #{account_id}" do
      fetch_locations_for_account(access_token, account_id)
    end
  rescue => e
    Rails.logger.error "[GoogleBusinessProfileService] Error fetching locations: #{e.message}"
    { error: 'Failed to fetch business locations' }
  end
  
  private
  
  # Exchange OAuth code for access and refresh tokens
  def exchange_code_for_tokens(code, redirect_uri)
    response = make_token_request({
      grant_type: 'authorization_code',
      client_id: @client_id,
      client_secret: @client_secret,
      redirect_uri: redirect_uri,
      code: code
    })
    
    return { error: 'Failed to exchange code for tokens' } unless response
    
    if response['access_token']
      expires_at = response['expires_in'] ? Time.current + response['expires_in'].seconds : nil
      
      {
        success: true,
        access_token: response['access_token'],
        refresh_token: response['refresh_token'],
        expires_at: expires_at
      }
    else
      Rails.logger.error "[GoogleBusinessProfileService] Token response missing access_token: #{response.inspect}"
      { error: response['error_description'] || 'Invalid OAuth response' }
    end
  end
  
  # Fetch business accounts from Google Business Profile API
  def fetch_business_accounts(access_token)
    response = make_api_request(ACCOUNTS_URL, access_token)
    return { error: 'Failed to fetch business accounts' } unless response
    
    if response['accounts']
      accounts = response['accounts'].map do |account|
        {
          account_id: account['name'],
          display_name: account['accountName'] || 'Business Account',
          type: account['type'] || 'PERSONAL'
        }
      end
      
      { success: true, accounts: accounts }
    else
      Rails.logger.error "[GoogleBusinessProfileService] Accounts response missing accounts: #{response.inspect}"
      { error: 'No business accounts found' }
    end
  end
  
  # Fetch locations for a specific business account
  def fetch_locations_for_account(access_token, account_id)
    # Clean account_id format (remove 'accounts/' prefix if present)
    clean_account_id = account_id.gsub(/^accounts\//, '')
    locations_url = "#{LOCATIONS_URL}/accounts/#{clean_account_id}/locations"
    
    response = make_api_request(locations_url, access_token)
    return { error: 'Failed to fetch business locations' } unless response
    
    if response['locations']
      locations = response['locations'].map do |location|
        {
          location_id: location['name'],
          business_name: location.dig('title') || location.dig('storefrontAddress', 'addressLines', 0) || 'Unknown Business',
          address: format_address(location['storefrontAddress']),
          phone: location['primaryPhone'],
          website: location['websiteUri'],
          place_id: location['metadata']&.dig('placeId')
        }
      end
      
      { success: true, locations: locations }
    else
      Rails.logger.info "[GoogleBusinessProfileService] No locations found for account #{account_id}"
      { success: true, locations: [] }
    end
  end
  
  # Make HTTP request to token endpoint
  def make_token_request(params)
    require 'net/http'
    require 'uri'
    require 'json'
    
    uri = URI(TOKEN_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 10
    http.open_timeout = 5
    
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/x-www-form-urlencoded'
    request.body = URI.encode_www_form(params)
    
    response = http.request(request)
    
    if response.code == '200'
      JSON.parse(response.body)
    else
      Rails.logger.error "[GoogleBusinessProfileService] Token request failed: #{response.code} #{response.body}"
      nil
    end
  rescue JSON::ParserError => e
    Rails.logger.error "[GoogleBusinessProfileService] JSON parse error in token request: #{e.message}"
    nil
  rescue => e
    Rails.logger.error "[GoogleBusinessProfileService] Token request error: #{e.message}"
    nil
  end
  
  # Make HTTP request to Business Profile API
  def make_api_request(url, access_token)
    require 'net/http'
    require 'uri'
    require 'json'
    
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 10
    http.open_timeout = 5
    
    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{access_token}"
    request['Content-Type'] = 'application/json'
    
    response = http.request(request)
    
    if response.code == '200'
      JSON.parse(response.body)
    else
      Rails.logger.error "[GoogleBusinessProfileService] API request failed: #{response.code} #{response.body}"
      nil
    end
  rescue JSON::ParserError => e
    Rails.logger.error "[GoogleBusinessProfileService] JSON parse error in API request: #{e.message}"
    nil
  rescue => e
    Rails.logger.error "[GoogleBusinessProfileService] API request error: #{e.message}"
    nil
  end
  
  # Format address from Google Business Profile format
  def format_address(address)
    return nil unless address
    
    parts = []
    parts.concat(address['addressLines']) if address['addressLines']
    parts << address['locality'] if address['locality']
    parts << address['administrativeArea'] if address['administrativeArea']
    parts << address['postalCode'] if address['postalCode']
    
    parts.compact.join(', ')
  end
end