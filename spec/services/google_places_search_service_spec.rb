# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GooglePlacesSearchService, type: :service do
  let(:service) { described_class.new }
  
  before do
    # Mock the API key
    allow(ENV).to receive(:[]).and_call_original
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
      let(:mock_search_response) do
        {
          'places' => [
            {
              'id' => 'ChIJN1t_tDeuEmsRUsoyG83frY4',
              'displayName' => { 'text' => 'Test Business' },
              'formattedAddress' => '123 Main St, New York, NY, USA',
              'types' => ['restaurant', 'food', 'establishment']
            },
            {
              'id' => 'ChIJAnother_Place_ID',
              'displayName' => { 'text' => 'Another Business' },
              'formattedAddress' => '456 Oak Ave, New York, NY, USA',
              'types' => ['store', 'establishment']
            }
          ]
        }
      end

      before do
        allow(service).to receive(:make_request_v1).and_return(mock_search_response)
      end

      it 'returns successful search results' do
        result = service.search_businesses('test query')

        expect(result[:success]).to be true
        expect(result[:businesses].size).to eq(2)
        expect(result[:total_results]).to eq(2)
        
        first_business = result[:businesses].first
        expect(first_business[:place_id]).to eq('ChIJN1t_tDeuEmsRUsoyG83frY4')
        expect(first_business[:name]).to eq('Test Business')
        expect(first_business[:address]).to eq('123 Main St, New York, NY, USA')
        expect(first_business[:types]).to eq(['restaurant', 'food', 'establishment'])
      end

      it 'calls v1 searchText endpoint' do
        expect(service).to receive(:make_request_v1).with(
          a_string_including('https://places.googleapis.com/v1/places:searchText'),
          method: :post,
          headers: hash_including('X-Goog-Api-Key', 'X-Goog-FieldMask'),
          body: kind_of(String)
        ).and_return(mock_search_response)

        service.search_businesses('test query', 'New York, NY')
      end

      it 'handles businesses without displayName gracefully' do
        response_without_name = {
          'places' => [
            {
              'id' => 'ChIJTest123',
              'formattedAddress' => 'Address only',
              'types' => ['establishment']
            }
          ]
        }

        allow(service).to receive(:make_request_v1).and_return(response_without_name)

        result = service.search_businesses('test query')
        expect(result[:businesses].first[:name]).to eq('Unknown Business')
      end
    end

    context 'when API request fails' do
      before do
        allow(service).to receive(:make_request_v1).and_return(nil)
      end

      it 'returns error message' do
        result = service.search_businesses('test query')
        expect(result[:error]).to eq('Failed to search businesses')
      end
    end

    context 'when an exception occurs' do
      before do
        allow(service).to receive(:make_request_v1).and_raise(StandardError.new('Network error'))
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
          'id' => 'ChIJN1t_tDeuEmsRUsoyG83frY4',
          'displayName' => { 'text' => 'Test Business' },
          'formattedAddress' => '123 Main St, New York, NY 10001, USA',
          'nationalPhoneNumber' => '(555) 123-4567',
          'websiteUri' => 'https://testbusiness.com',
          'rating' => 4.5,
          'userRatingCount' => 123,
          'googleMapsUri' => 'https://maps.google.com/test',
          'types' => ['restaurant', 'food', 'establishment']
        }
      end

      before do
        allow(service).to receive(:make_request_v1).and_return(mock_details_response)
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
        expect(business[:business_status]).to be_nil
        expect(business[:rating]).to eq(4.5)
        expect(business[:total_ratings]).to eq(123)
        expect(business[:google_url]).to eq('https://maps.google.com/test')
        expect(business[:types]).to eq(['restaurant', 'food', 'establishment'])
      end

      it 'parses minimal v1 fields without photos/reviews collections' do
        result = service.get_business_details('ChIJN1t_tDeuEmsRUsoyG83frY4')
        expect(result[:business][:photos]).to eq([])
        expect(result[:business][:recent_reviews]).to eq([])
      end
    end

    context 'when business is permanently closed' do
      let(:closed_business_response) do
        {
          'id' => 'ChIJClosed_Business',
          'displayName' => { 'text' => 'Closed Business' }
        }
      end

      before do
        allow(service).to receive(:make_request_v1).and_return(closed_business_response)
      end

      it 'returns success (v1 does not include closed status by default)' do
        result = service.get_business_details('ChIJClosed_Business')
        expect(result[:success]).to be true
        expect(result[:business][:name]).to eq('Closed Business')
      end
    end

    context 'when API request fails' do
      before do
        allow(service).to receive(:make_request_v1).and_return(nil)
      end

      it 'returns error message' do
        result = service.get_business_details('test_place_id')
        expect(result[:error]).to eq('Failed to fetch business details')
      end
    end

    context 'when response is invalid' do
      before do
        allow(service).to receive(:make_request_v1).and_return(nil)
      end

      it 'returns error message' do
        result = service.get_business_details('test_place_id')
        expect(result[:error]).to eq('Failed to fetch business details')
      end
    end
  end

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
        result = service.send(:make_request_v1, url, method: :get, headers: { 'X-Test' => '1' })
        expect(result).to eq({ 'success' => true })
      end

      it 'sets proper HTTP options and headers' do
        expect(mock_http).to receive(:use_ssl=).with(true)
        expect(mock_http).to receive(:read_timeout=).with(10)
        expect(mock_http).to receive(:open_timeout=).with(5)
        
        service.send(:make_request_v1, url, method: :get, headers: { 'User-Agent' => 'BizBlasts Test' })
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
        result = service.send(:make_request_v1, url, method: :get, headers: { })
        
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
        result = service.send(:make_request_v1, url, method: :get, headers: { })
        
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
        result = service.send(:make_request_v1, url, method: :get, headers: { })
        
        expect(Rails.logger).to have_received(:error)
          .with(match(/JSON parse error/))
        expect(result).to be_nil
      end
    end
  end
end