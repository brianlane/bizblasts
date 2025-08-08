# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoogleReviewsService, type: :service do
  let(:business) { create(:business, google_place_id: 'ChIJN1t_tDeuEmsRUsoyG83frY4') }
  let(:business_without_place_id) { create(:business, google_place_id: nil) }
  let(:service) { described_class.new(business) }
  
  before do
    Rails.cache.clear
    # Mock the API key
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
          'result' => {
            'name' => 'Test Business',
            'rating' => 4.5,
            'user_ratings_total' => 123,
            'url' => 'https://maps.google.com/test',
            'reviews' => [
              {
                'author_name' => 'John Doe',
                'author_url' => 'https://maps.google.com/user1',
                'profile_photo_url' => 'https://maps.google.com/photo1.jpg',
                'rating' => 5,
                'relative_time_description' => '2 days ago',
                'text' => 'Great service!',
                'time' => 1641024000
              },
              {
                'author_name' => 'Jane Smith',
                'author_url' => 'https://maps.google.com/user2',
                'profile_photo_url' => 'https://maps.google.com/photo2.jpg',
                'rating' => 4,
                'relative_time_description' => '1 week ago',
                'text' => 'Good experience overall.',
                'time' => 1640419200
              }
            ]
          }
        }
      end

      before do
        allow(service).to receive(:make_request).and_return(mock_response)
      end

      it 'returns structured review data' do
        result = service.fetch

        expect(result[:success]).to be true
        expect(result[:place][:name]).to eq('Test Business')
        expect(result[:place][:rating]).to eq(4.5)
        expect(result[:place][:user_ratings_total]).to eq(123)
        expect(result[:place][:google_url]).to eq('https://maps.google.com/test')
        
        expect(result[:reviews]).to have(2).items
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
        expect(first_review[:time]).to eq(Time.at(1641024000))
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
        
        mock_response['result']['reviews'] = many_reviews
        allow(service).to receive(:make_request).and_return(mock_response)

        result = service.fetch
        expect(result[:reviews]).to have(5).items
      end

      it 'caches results for 1 hour' do
        # First call
        result1 = service.fetch
        
        # Mock different response for second call
        different_response = mock_response.dup
        different_response['result']['name'] = 'Different Business'
        allow(service).to receive(:make_request).and_return(different_response)
        
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
        allow(service).to receive(:make_request).and_return(nil)
      end

      it 'returns error message' do
        result = service.fetch
        expect(result[:error]).to eq('Failed to fetch reviews')
      end
    end

    context 'when API returns invalid response' do
      before do
        allow(service).to receive(:make_request).and_return({ 'invalid' => 'response' })
      end

      it 'returns error message' do
        result = service.fetch
        expect(result[:error]).to eq('Invalid API response')
      end
    end

    context 'when an exception occurs' do
      before do
        allow(service).to receive(:make_request).and_raise(StandardError.new('Network error'))
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

  describe '#build_api_url' do
    it 'constructs correct API URL' do
      url = service.send(:build_api_url)
      
      expect(url).to include('https://maps.googleapis.com/maps/api/place/details/json')
      expect(url).to include("place_id=#{business.google_place_id}")
      expect(url).to include('key=test_api_key')
      expect(url).to include('fields=rating%2Creviews%2Curl%2Cuser_ratings_total%2Cname')
    end
  end

  describe '#make_request' do
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
        result = service.send(:make_request, url)
        expect(result).to eq({ 'success' => true })
      end

      it 'sets proper HTTP options' do
        expect(mock_http).to receive(:use_ssl=).with(true)
        expect(mock_http).to receive(:read_timeout=).with(10)
        expect(mock_http).to receive(:open_timeout=).with(5)
        
        service.send(:make_request, url)
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
        result = service.send(:make_request, url)
        
        expect(Rails.logger).to have_received(:error)
          .with(match(/API request failed: 404/))
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
        allow(mock_http).to receive(:request).and_raise(Net::TimeoutError.new('Timeout'))
        allow(Rails.logger).to receive(:error)
      end

      it 'logs timeout error and returns nil' do
        result = service.send(:make_request, url)
        
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
        result = service.send(:make_request, url)
        
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

  describe '#process_review' do
    let(:review_data) do
      {
        'author_name' => 'Test Author',
        'author_url' => 'https://maps.google.com/user',
        'profile_photo_url' => 'https://maps.google.com/photo.jpg',
        'rating' => 5,
        'relative_time_description' => '1 day ago',
        'text' => 'Excellent service!',
        'time' => 1641024000
      }
    end

    it 'processes review data correctly' do
      result = service.send(:process_review, review_data)
      
      expect(result[:author_name]).to eq('Test Author')
      expect(result[:author_url]).to eq('https://maps.google.com/user')
      expect(result[:profile_photo_url]).to eq('https://maps.google.com/photo.jpg')
      expect(result[:rating]).to eq(5)
      expect(result[:relative_time_description]).to eq('1 day ago')
      expect(result[:text]).to eq('Excellent service!')
      expect(result[:time]).to eq(Time.at(1641024000))
    end

    it 'handles missing time field' do
      review_data.delete('time')
      result = service.send(:process_review, review_data)
      expect(result[:time]).to be_nil
    end
  end
end