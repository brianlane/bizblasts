# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GooglePlacesSearchService, type: :service do
  let(:service) { described_class.new }
  
  before do
    # Mock the API key
    allow(ENV).to receive(:[]).with('GOOGLE_API_KEY').and_return('test_api_key')
  end

  describe '.search_businesses' do
    it 'delegates to instance method' do
      expect_any_instance_of(described_class).to receive(:search_businesses).with('test query', 'test location')
      described_class.search_businesses('test query', 'test location')
    end
  end

  describe '.get_business_details' do
    it 'delegates to instance method' do
      expect_any_instance_of(described_class).to receive(:get_business_details).with('test_place_id')
      described_class.get_business_details('test_place_id')
    end
  end

  describe '#search_businesses' do
    context 'when API key is not configured' do
      before do
        allow(ENV).to receive(:[]).with('GOOGLE_API_KEY').and_return(nil)
      end

      it 'returns error message' do
        result = service.search_businesses('test query')
        expect(result[:error]).to eq('Google API key not configured')
      end
    end

    context 'when query is blank' do
      it 'returns error for nil query' do
        result = service.search_businesses(nil)
        expect(result[:error]).to eq('Search query is required')
      end

      it 'returns error for empty query' do
        result = service.search_businesses('')
        expect(result[:error]).to eq('Search query is required')
      end

      it 'returns error for whitespace-only query' do
        result = service.search_businesses('   ')
        expect(result[:error]).to eq('Search query is required')
      end
    end

    context 'with valid configuration' do
      let(:mock_autocomplete_response) do
        {
          'predictions' => [
            {
              'place_id' => 'ChIJN1t_tDeuEmsRUsoyG83frY4',
              'description' => 'Test Business, 123 Main St, New York, NY, USA',
              'structured_formatting' => {
                'main_text' => 'Test Business',
                'secondary_text' => '123 Main St, New York, NY, USA'
              },
              'types' => ['restaurant', 'food', 'establishment'],
              'matched_substrings' => [{ 'offset' => 0, 'length' => 4 }]
            },
            {
              'place_id' => 'ChIJAnother_Place_ID',
              'description' => 'Another Business, 456 Oak Ave, New York, NY, USA',
              'structured_formatting' => {
                'main_text' => 'Another Business',
                'secondary_text' => '456 Oak Ave, New York, NY, USA'
              },
              'types' => ['store', 'establishment'],
              'matched_substrings' => [{ 'offset' => 0, 'length' => 7 }]
            }
          ]
        }
      end

      before do
        allow(service).to receive(:make_request).and_return(mock_autocomplete_response)
      end

      it 'returns successful search results' do
        result = service.search_businesses('test query')

        expect(result[:success]).to be true
        expect(result[:businesses]).to have(2).items
        expect(result[:total_results]).to eq(2)
        
        first_business = result[:businesses].first
        expect(first_business[:place_id]).to eq('ChIJN1t_tDeuEmsRUsoyG83frY4')
        expect(first_business[:name]).to eq('Test Business')
        expect(first_business[:address]).to eq('Test Business, 123 Main St, New York, NY, USA')
        expect(first_business[:types]).to eq(['restaurant', 'food', 'establishment'])
      end

      it 'includes location bias when location is provided' do
        expect(service).to receive(:make_request) do |url|
          expect(url).to include('locationbias=circle:50000@New+York%2C+NY')
          mock_autocomplete_response
        end

        service.search_businesses('test query', 'New York, NY')
      end

      it 'does not include location bias when location is not provided' do
        expect(service).to receive(:make_request) do |url|
          expect(url).not_to include('locationbias')
          mock_autocomplete_response
        end

        service.search_businesses('test query')
      end

      it 'handles businesses without structured formatting' do
        response_without_formatting = {
          'predictions' => [
            {
              'place_id' => 'ChIJTest123',
              'description' => 'Simple Business Name, Address',
              'types' => ['establishment']
            }
          ]
        }

        allow(service).to receive(:make_request).and_return(response_without_formatting)

        result = service.search_businesses('test query')
        expect(result[:businesses].first[:name]).to eq('Simple Business Name')
      end
    end

    context 'when API request fails' do
      before do
        allow(service).to receive(:make_request).and_return(nil)
      end

      it 'returns error message' do
        result = service.search_businesses('test query')
        expect(result[:error]).to eq('Failed to search businesses')
      end
    end

    context 'when an exception occurs' do
      before do
        allow(service).to receive(:make_request).and_raise(StandardError.new('Network error'))
        allow(Rails.logger).to receive(:error)
      end

      it 'logs error and returns generic error message' do
        result = service.search_businesses('test query')
        
        expect(Rails.logger).to have_received(:error)
          .with(match(/Error searching businesses.*Network error/))
        expect(result[:error]).to eq('Unable to search for businesses at this time')
      end
    end
  end

  describe '#get_business_details' do
    context 'when API key is not configured' do
      before do
        allow(ENV).to receive(:[]).with('GOOGLE_API_KEY').and_return(nil)
      end

      it 'returns error message' do
        result = service.get_business_details('test_place_id')
        expect(result[:error]).to eq('Google API key not configured')
      end
    end

    context 'when place_id is blank' do
      it 'returns error for nil place_id' do
        result = service.get_business_details(nil)
        expect(result[:error]).to eq('Place ID is required')
      end

      it 'returns error for empty place_id' do
        result = service.get_business_details('')
        expect(result[:error]).to eq('Place ID is required')
      end
    end

    context 'with valid configuration' do
      let(:mock_details_response) do
        {
          'result' => {
            'place_id' => 'ChIJN1t_tDeuEmsRUsoyG83frY4',
            'name' => 'Test Business',
            'formatted_address' => '123 Main St, New York, NY 10001, USA',
            'formatted_phone_number' => '(555) 123-4567',
            'website' => 'https://testbusiness.com',
            'business_status' => 'OPERATIONAL',
            'rating' => 4.5,
            'user_ratings_total' => 123,
            'url' => 'https://maps.google.com/test',
            'types' => ['restaurant', 'food', 'establishment'],
            'photos' => [
              {
                'photo_reference' => 'photo_ref_1',
                'width' => 400,
                'height' => 300
              },
              {
                'photo_reference' => 'photo_ref_2',
                'width' => 800,
                'height' => 600
              }
            ],
            'reviews' => [
              {
                'author_name' => 'John Doe',
                'rating' => 5,
                'text' => 'Great food and excellent service! Highly recommend this place.',
                'relative_time_description' => '2 days ago'
              },
              {
                'author_name' => 'Jane Smith',
                'rating' => 4,
                'text' => 'Good experience overall, but could use some improvement in the ambiance.',
                'relative_time_description' => '1 week ago'
              }
            ]
          }
        }
      end

      before do
        allow(service).to receive(:make_request).and_return(mock_details_response)
      end

      it 'returns detailed business information' do
        result = service.get_business_details('ChIJN1t_tDeuEmsRUsoyG83frY4')

        expect(result[:success]).to be true
        business = result[:business]
        
        expect(business[:place_id]).to eq('ChIJN1t_tDeuEmsRUsoyG83frY4')
        expect(business[:name]).to eq('Test Business')
        expect(business[:address]).to eq('123 Main St, New York, NY 10001, USA')
        expect(business[:phone]).to eq('(555) 123-4567')
        expect(business[:website]).to eq('https://testbusiness.com')
        expect(business[:business_status]).to eq('OPERATIONAL')
        expect(business[:rating]).to eq(4.5)
        expect(business[:total_ratings]).to eq(123)
        expect(business[:google_url]).to eq('https://maps.google.com/test')
        expect(business[:types]).to eq(['restaurant', 'food', 'establishment'])
      end

      it 'includes processed photos' do
        result = service.get_business_details('ChIJN1t_tDeuEmsRUsoyG83frY4')
        photos = result[:business][:photos]
        
        expect(photos).to have(2).items
        expect(photos.first[:reference]).to eq('photo_ref_1')
        expect(photos.first[:url]).to include('photo_reference=photo_ref_1')
        expect(photos.first[:width]).to eq(400)
        expect(photos.first[:height]).to eq(300)
      end

      it 'includes processed reviews' do
        result = service.get_business_details('ChIJN1t_tDeuEmsRUsoyG83frY4')
        reviews = result[:business][:recent_reviews]
        
        expect(reviews).to have(2).items
        expect(reviews.first[:author]).to eq('John Doe')
        expect(reviews.first[:rating]).to eq(5)
        expect(reviews.first[:text]).to include('Great food')
        expect(reviews.first[:time]).to eq('2 days ago')
      end

      it 'truncates long review text' do
        long_review_response = mock_details_response.dup
        long_review_response['result']['reviews'][0]['text'] = 'A' * 200
        allow(service).to receive(:make_request).and_return(long_review_response)

        result = service.get_business_details('ChIJN1t_tDeuEmsRUsoyG83frY4')
        review_text = result[:business][:recent_reviews].first[:text]
        
        expect(review_text.length).to be <= 150
        expect(review_text).to end_with('...')
      end

      it 'limits photos to first 3' do
        many_photos_response = mock_details_response.dup
        many_photos_response['result']['photos'] = Array.new(10) do |i|
          { 'photo_reference' => "photo_ref_#{i}", 'width' => 400, 'height' => 300 }
        end
        allow(service).to receive(:make_request).and_return(many_photos_response)

        result = service.get_business_details('ChIJN1t_tDeuEmsRUsoyG83frY4')
        expect(result[:business][:photos]).to have(3).items
      end

      it 'limits reviews to first 3' do
        many_reviews_response = mock_details_response.dup
        many_reviews_response['result']['reviews'] = Array.new(10) do |i|
          {
            'author_name' => "Author #{i}",
            'rating' => 4,
            'text' => "Review #{i}",
            'relative_time_description' => "#{i} days ago"
          }
        end
        allow(service).to receive(:make_request).and_return(many_reviews_response)

        result = service.get_business_details('ChIJN1t_tDeuEmsRUsoyG83frY4')
        expect(result[:business][:recent_reviews]).to have(3).items
      end
    end

    context 'when business is permanently closed' do
      let(:closed_business_response) do
        {
          'result' => {
            'place_id' => 'ChIJClosed_Business',
            'name' => 'Closed Business',
            'business_status' => 'CLOSED_PERMANENTLY'
          }
        }
      end

      before do
        allow(service).to receive(:make_request).and_return(closed_business_response)
      end

      it 'returns appropriate error message' do
        result = service.get_business_details('ChIJClosed_Business')
        expect(result[:error]).to eq('This business is marked as permanently closed on Google')
      end
    end

    context 'when API request fails' do
      before do
        allow(service).to receive(:make_request).and_return(nil)
      end

      it 'returns error message' do
        result = service.get_business_details('test_place_id')
        expect(result[:error]).to eq('Failed to fetch business details')
      end
    end

    context 'when response is invalid' do
      before do
        allow(service).to receive(:make_request).and_return({ 'invalid' => 'response' })
      end

      it 'returns error message' do
        result = service.get_business_details('test_place_id')
        expect(result[:error]).to eq('Invalid business details response')
      end
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

      it 'sets proper HTTP options and headers' do
        expect(mock_http).to receive(:use_ssl=).with(true)
        expect(mock_http).to receive(:read_timeout=).with(10)
        expect(mock_http).to receive(:open_timeout=).with(5)
        
        expect_any_instance_of(Net::HTTP::Get).to receive(:[]=).with('User-Agent', match(/BizBlasts/))
        
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
end