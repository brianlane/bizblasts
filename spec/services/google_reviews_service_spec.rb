# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoogleReviewsService, type: :service do
  let(:business) { create(:business, google_place_id: 'ChIJN1t_tDeuEmsRUsoyG83frY4') }
  let(:business_without_place_id) { create(:business, google_place_id: nil) }
  let(:service) { described_class.new(business) }
  
  before do
    Rails.cache.clear
    # Mock the API key
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('GOOGLE_API_KEY').and_return('test_api_key')
  end

  describe '.fetch' do
    it 'returns result from instance method' do
      result = { success: true, reviews: [] }
      expect_any_instance_of(described_class).to receive(:fetch).and_return(result)
      expect(described_class.fetch(business)).to eq(result)
    end
  end

  describe '#fetch' do
    context 'when business has no Google Place ID' do
      let(:service) { described_class.new(business_without_place_id) }

      it 'returns error message' do
        result = service.fetch
        expect(result[:error]).to eq('Google Place ID not configured')
      end
    end

    context 'when business has google_business_profile_id but no google_place_id' do
      let(:business_with_profile_id) { create(:business, google_place_id: nil, google_business_profile_id: 'ChIJProfileID123456') }
      let(:service) { described_class.new(business_with_profile_id) }

      it 'uses google_business_profile_id for API calls' do
        expect(service.instance_variable_get(:@place_id)).to eq('ChIJProfileID123456')
      end
    end

    context 'when business has both google_place_id and google_business_profile_id' do
      let(:business_with_both) { create(:business, google_place_id: 'ChIJPlaceID123', google_business_profile_id: 'ChIJProfileID456') }
      let(:service) { described_class.new(business_with_both) }

      it 'prioritizes google_place_id over google_business_profile_id' do
        expect(service.instance_variable_get(:@place_id)).to eq('ChIJPlaceID123')
      end
    end

    context 'when Google API key is not configured' do
      before do
        allow(ENV).to receive(:[]).with('GOOGLE_API_KEY').and_return(nil)
      end

      it 'returns error message' do
        result = service.fetch
        expect(result[:error]).to eq('Google API key not configured')
      end
    end

    context 'with valid configuration' do
      let(:mock_response) do
        {
          'displayName' => { 'text' => 'Test Business' },
          'rating' => 4.5,
          'userRatingCount' => 123,
          'googleMapsUri' => 'https://maps.google.com/test',
          'reviews' => [
            {
              'authorAttribution' => {
                'displayName' => 'John Doe',
                'uri' => 'https://maps.google.com/user1',
                'photoUri' => 'https://maps.google.com/photo1.jpg'
              },
              'rating' => 5,
              'text' => 'Great service!',
              'publishTime' => '2022-01-01T00:00:00Z'
            },
            {
              'authorAttribution' => {
                'displayName' => 'Jane Smith',
                'uri' => 'https://maps.google.com/user2',
                'photoUri' => 'https://maps.google.com/photo2.jpg'
              },
              'rating' => 4,
              'text' => 'Good experience overall.',
              'publishTime' => '2021-12-25T00:00:00Z'
            }
          ]
        }
      end

      before do
        allow(service).to receive(:make_request_v1).and_return(mock_response)
      end

      it 'returns structured review data' do
        result = service.fetch

        expect(result[:success]).to be true
        expect(result[:place][:name]).to eq('Test Business')
        expect(result[:place][:rating]).to eq(4.5)
        expect(result[:place][:user_ratings_total]).to eq(123)
        expect(result[:place][:google_url]).to eq('https://maps.google.com/test')
        
        expect(result[:reviews].size).to eq(2)
        expect(result[:reviews].first[:author_name]).to eq('John Doe')
        expect(result[:reviews].first[:rating]).to eq(5)
        expect(result[:reviews].first[:text]).to eq('Great service!')
        
        expect(result[:google_url]).to eq("https://search.google.com/local/writereview?placeid=#{business.google_place_id}")
        expect(result[:fetched_at]).to be_present
      end

      it 'processes review times correctly' do
        result = service.fetch
        first_review = result[:reviews].first
        expect(first_review[:time]).to be_a(Time)
        expect(first_review[:time]).to eq(Time.parse('2022-01-01T00:00:00Z'))
      end

      it 'limits reviews to MAX_REVIEWS' do
        # Create response with more than MAX_REVIEWS (5) reviews
        many_reviews = Array.new(10) do |i|
          {
            'author_name' => "User #{i}",
            'rating' => 4,
            'text' => "Review #{i}",
            'time' => 1641024000
          }
        end
        
        mock_response['reviews'] = many_reviews.map do |r|
          {
            'authorAttribution' => { 'displayName' => r['author_name'] },
            'rating' => r['rating'],
            'text' => r['text'],
            'publishTime' => '2022-01-01T00:00:00Z'
          }
        end
        allow(service).to receive(:make_request_v1).and_return(mock_response)

        result = service.fetch
        expect(result[:reviews].size).to eq(5)
      end

      it 'caches results for 1 hour' do
        # First call
        result1 = service.fetch
        
        # Mock different response for second call
        different_response = mock_response.dup
        different_response['displayName'] = { 'text' => 'Different Business' }
        allow(service).to receive(:make_request_v1).and_return(different_response)
        
        # Second call should return cached result
        result2 = service.fetch
        expect(result2[:place][:name]).to eq('Test Business') # Still cached
        
        # Clear cache and try again
        Rails.cache.clear
        result3 = service.fetch
        expect(result3[:place][:name]).to eq('Different Business') # New result
      end

      it 'generates correct cache key' do
        expect(Rails.cache).to receive(:fetch)
          .with("google_reviews_#{business.id}_#{business.google_place_id}", { expires_in: 1.hour })
          .and_call_original
        
        service.fetch
      end
    end

    context 'when API request fails' do
      before do
        allow(service).to receive(:make_request_v1).and_return(nil)
      end

      it 'returns error message' do
        result = service.fetch
        expect(result[:error]).to eq('Failed to fetch reviews')
      end
    end

    context 'when API returns invalid response' do
      before do
        allow(service).to receive(:make_request_v1).and_return('invalid')
      end

      it 'returns error message' do
        result = service.fetch
        expect(result[:error]).to eq('Invalid API response')
      end
    end

    context 'when an exception occurs' do
      before do
        allow(service).to receive(:make_request_v1).and_raise(StandardError.new('Network error'))
        allow(Rails.logger).to receive(:error)
      end

      it 'logs error and returns generic error message' do
        result = service.fetch
        
        expect(Rails.logger).to have_received(:error)
          .with(match(/Error fetching reviews for business #{business.id}/))
        expect(result[:error]).to eq('Unable to fetch reviews at this time')
      end
    end
  end

  # build_api_url removed in v1 implementation

  describe '#make_request_v1' do
    let(:url) { 'https://example.com/api' }
    
    context 'with successful HTTP response' do
      let(:response_body) { '{"success": true}' }
      let(:mock_response) { double(code: '200', body: response_body) }
      let(:mock_http) { double }

      before do
        allow(Net::HTTP).to receive(:new).and_return(mock_http)
        allow(mock_http).to receive(:use_ssl=)
        allow(mock_http).to receive(:read_timeout=)
        allow(mock_http).to receive(:open_timeout=)
        allow(mock_http).to receive(:request).and_return(mock_response)
      end

      it 'returns parsed JSON' do
        result = service.send(:make_request_v1, url, headers: { 'X-Test' => '1' })
        expect(result).to eq({ 'success' => true })
      end

      it 'sets proper HTTP options' do
        expect(mock_http).to receive(:use_ssl=).with(true)
        expect(mock_http).to receive(:read_timeout=).with(10)
        expect(mock_http).to receive(:open_timeout=).with(5)
        
        service.send(:make_request_v1, url, headers: { 'X-Test' => '1' })
      end
    end

    context 'with HTTP error response' do
      let(:mock_response) { double(code: '404', body: 'Not Found') }
      let(:mock_http) { double }

      before do
        allow(Net::HTTP).to receive(:new).and_return(mock_http)
        allow(mock_http).to receive(:use_ssl=)
        allow(mock_http).to receive(:read_timeout=)
        allow(mock_http).to receive(:open_timeout=)
        allow(mock_http).to receive(:request).and_return(mock_response)
        allow(Rails.logger).to receive(:error)
      end

      it 'logs error and returns nil' do
        result = service.send(:make_request_v1, url, headers: { })
        
        expect(Rails.logger).to have_received(:error)
          .with(match(/API v1 request failed: 404/))
        expect(result).to be_nil
      end
    end

    context 'with network timeout' do
      let(:mock_http) { double }

      before do
        allow(Net::HTTP).to receive(:new).and_return(mock_http)
        allow(mock_http).to receive(:use_ssl=)
        allow(mock_http).to receive(:read_timeout=)
        allow(mock_http).to receive(:open_timeout=)
        allow(mock_http).to receive(:request).and_raise(Timeout::Error.new('Timeout'))
        allow(Rails.logger).to receive(:error)
      end

      it 'logs timeout error and returns nil' do
        result = service.send(:make_request_v1, url, headers: { })
        
        expect(Rails.logger).to have_received(:error)
          .with(match(/Timeout error/))
        expect(result).to be_nil
      end
    end

    context 'with JSON parse error' do
      let(:mock_response) { double(code: '200', body: 'invalid json') }
      let(:mock_http) { double }

      before do
        allow(Net::HTTP).to receive(:new).and_return(mock_http)
        allow(mock_http).to receive(:use_ssl=)
        allow(mock_http).to receive(:read_timeout=)
        allow(mock_http).to receive(:open_timeout=)
        allow(mock_http).to receive(:request).and_return(mock_response)
        allow(Rails.logger).to receive(:error)
      end

      it 'logs parse error and returns nil' do
        result = service.send(:make_request_v1, url, headers: { })
        
        expect(Rails.logger).to have_received(:error)
          .with(match(/JSON parse error/))
        expect(result).to be_nil
      end
    end
  end

  describe '#generate_google_reviews_url' do
    it 'generates correct Google review URL' do
      url = service.send(:generate_google_reviews_url)
      expect(url).to eq("https://search.google.com/local/writereview?placeid=#{business.google_place_id}")
    end
  end

  describe '#process_review_v1' do
    let(:review_data) do
      {
        'authorAttribution' => {
          'displayName' => 'Test Author',
          'uri' => 'https://maps.google.com/user',
          'photoUri' => 'https://maps.google.com/photo.jpg'
        },
        'rating' => 5,
        'text' => 'Excellent service!',
        'publishTime' => '2022-01-01T00:00:00Z'
      }
    end

    it 'processes review data correctly' do
      result = service.send(:process_review_v1, review_data)
      
      expect(result[:author_name]).to eq('Test Author')
      expect(result[:author_url]).to eq('https://maps.google.com/user')
      expect(result[:profile_photo_url]).to eq('https://maps.google.com/photo.jpg')
      expect(result[:rating]).to eq(5)
      expect(result[:text]).to eq('Excellent service!')
      expect(result[:time]).to eq(Time.parse('2022-01-01T00:00:00Z'))
    end

    it 'handles missing time field' do
      review_data.delete('publishTime')
      result = service.send(:process_review_v1, review_data)
      expect(result[:time]).to be_nil
    end
  end
end