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

  # Security tests for ReDoS vulnerabilities and edge cases
  describe 'security and edge case handling' do
    describe '#clean_business_name (private method)' do
      it 'handles very long strings without performance degradation' do
        # Test that we avoid ReDoS with long repetitive input
        long_string = 'Business ' + ('& ' * 500) + 'Services'

        start_time = Time.now
        result = service.send(:clean_business_name, long_string)
        end_time = Time.now

        expect(end_time - start_time).to be < 1.0 # Should complete in less than 1 second
        expect(result).to be_a(String)
      end

      it 'safely removes business suffixes without regex' do
        expect(service.send(:clean_business_name, 'ABC Company & Protection')).to eq('ABC Company')
        expect(service.send(:clean_business_name, 'XYZ Corp and Services')).to eq('XYZ Corp')
        expect(service.send(:clean_business_name, 'Test Business & LLC')).to eq('Test Business')
      end

      it 'handles case-insensitive suffix removal' do
        expect(service.send(:clean_business_name, 'Business & PROTECTION')).to eq('Business')
        expect(service.send(:clean_business_name, 'Business AND services')).to eq('Business')
      end

      it 'removes detail prefixes safely' do
        expect(service.send(:clean_business_name, 'Detail & Car Wash')).to eq('Car Wash')
        expect(service.send(:clean_business_name, 'Auto and Detailing Shop')).to eq('Detailing Shop')
      end

      it 'cleans up multiple spaces' do
        expect(service.send(:clean_business_name, 'Business   with    spaces')).to eq('Business with spaces')
      end

      it 'handles edge cases safely' do
        expect(service.send(:clean_business_name, '')).to eq('')
        expect(service.send(:clean_business_name, '   ')).to eq('')
        expect(service.send(:clean_business_name, 'A')).to eq('A')
      end

      it 'limits input length to prevent attacks' do
        very_long_string = 'a' * 250
        result = service.send(:clean_business_name, very_long_string)
        expect(result).to eq(very_long_string) # Should return unchanged for very long strings
      end
    end

    describe '#extract_core_business_name (private method)' do
      it 'handles possessive names case-insensitively' do
        # Bug fix: Should handle "Joe'S" (uppercase S) correctly
        expect(service.send(:extract_core_business_name, "Joe's Car Wash")).to eq("Joe's Car")
        expect(service.send(:extract_core_business_name, "Joe'S Car Wash")).to eq("Joe'S Car")
        expect(service.send(:extract_core_business_name, "Mike's Auto Shop")).to eq("Mike's Auto")
        expect(service.send(:extract_core_business_name, "MIKE'S AUTO SHOP")).to eq("MIKE'S AUTO")
      end

      it 'extracts first 1-2 words for non-possessive names' do
        expect(service.send(:extract_core_business_name, "ABC Company")).to eq("ABC Company")
        expect(service.send(:extract_core_business_name, "XYZ Corp Detail Shop")).to eq("XYZ Corp")
      end

      it 'handles single word names' do
        expect(service.send(:extract_core_business_name, "Business")).to eq("Business")
      end
    end

    describe 'query variation generation' do
      it 'generates safe query variations without ReDoS risk' do
        query = 'Auto Detail & Protection Services'
        location = 'Phoenix, AZ'

        variations = service.send(:generate_query_variations, query, location)

        expect(variations).to be_an(Array)
        expect(variations.length).to be > 0
        expect(variations.all? { |v| v[:query].is_a?(String) }).to be true
      end

      it 'handles malicious input safely' do
        # Test with potentially problematic patterns
        malicious_query = 'a' * 100 + ' & ' + 'b' * 100

        start_time = Time.now
        variations = service.send(:generate_query_variations, malicious_query, nil)
        end_time = Time.now

        expect(end_time - start_time).to be < 1.0
        expect(variations).to be_an(Array)
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