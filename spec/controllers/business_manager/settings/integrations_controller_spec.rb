# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BusinessManager::Settings::IntegrationsController, type: :controller do
  let(:business) { create(:business) }
  let(:user) { create(:user, :manager, business: business) }

  before do
    request.host = host_for(business)
    ActsAsTenant.current_tenant = business
    sign_in user
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe 'GET #google_business_search' do
    context 'when query is provided' do
      let(:search_results) do
        {
          success: true,
          businesses: [
            {
              place_id: 'ChIJN1t_tDeuEmsRUsoyG83frY4',
              name: 'Test Business',
              address: '123 Main St, New York, NY, USA',
              types: ['restaurant', 'establishment']
            }
          ],
          total_results: 1
        }
      end

      before do
        allow(GooglePlacesSearchService).to receive(:search_businesses).and_return(search_results)
      end

      it 'returns search results' do
        get :google_business_search, params: { query: 'Test Business' }, format: :json

        expect(response).to have_http_status(:success)
        expect(json_response['success']).to be true
        expect(json_response['businesses'].length).to eq(1)
        expect(json_response['businesses'].first['name']).to eq('Test Business')
      end

      it 'calls search service with query and location' do
        expect(GooglePlacesSearchService).to receive(:search_businesses)
          .with('Test Business', 'New York, NY')
          .and_return(search_results)

        get :google_business_search, params: { query: 'Test Business', location: 'New York, NY' }, format: :json
      end

      it 'uses business address as location context when not provided' do
        business.update!(address: '456 Oak Ave', city: 'Los Angeles', state: 'CA')
        
        expect(GooglePlacesSearchService).to receive(:search_businesses)
          .with('Test Business', '456 Oak Ave, Los Angeles, CA')
          .and_return(search_results)

        get :google_business_search, params: { query: 'Test Business' }, format: :json
      end
    end

    context 'when query is blank' do
      it 'returns bad request error' do
        get :google_business_search, params: { query: '' }, format: :json

        expect(response).to have_http_status(:bad_request)
        expect(json_response['error']).to eq('Search query is required')
      end

      it 'returns bad request for nil query' do
        get :google_business_search, format: :json

        expect(response).to have_http_status(:bad_request)
        expect(json_response['error']).to eq('Search query is required')
      end
    end

    context 'when search service returns error' do
      before do
        allow(GooglePlacesSearchService).to receive(:search_businesses)
          .and_return({ error: 'API error' })
      end

      it 'returns the service error' do
        get :google_business_search, params: { query: 'Test Business' }, format: :json

        expect(response).to have_http_status(:success)
        expect(json_response['error']).to eq('API error')
      end
    end

    context 'when an exception occurs' do
      before do
        allow(GooglePlacesSearchService).to receive(:search_businesses)
          .and_raise(StandardError.new('Service error'))
        allow(Rails.logger).to receive(:error)
      end

      it 'returns internal server error' do
        get :google_business_search, params: { query: 'Test Business' }, format: :json

        expect(response).to have_http_status(:internal_server_error)
        expect(json_response['error']).to eq('Search failed')
        expect(Rails.logger).to have_received(:error)
          .with(match(/Google Business search error.*Service error/))
      end
    end
  end

  describe 'GET #google_business_details' do
    let(:place_id) { 'ChIJN1t_tDeuEmsRUsoyG83frY4' }
    let(:business_details) do
      {
        success: true,
        business: {
          place_id: place_id,
          name: 'Test Business',
          address: '123 Main St, New York, NY, USA',
          phone: '(555) 123-4567',
          website: 'https://testbusiness.com',
          rating: 4.5,
          total_ratings: 123
        }
      }
    end

    before do
      allow(GooglePlacesSearchService).to receive(:get_business_details).and_return(business_details)
    end

    it 'returns business details' do
      get :google_business_details, params: { place_id: place_id }, format: :json

      expect(response).to have_http_status(:success)
      expect(json_response['success']).to be true
      expect(json_response['business']['name']).to eq('Test Business')
      expect(json_response['business']['rating']).to eq(4.5)
    end

    it 'calls details service with place_id' do
      expect(GooglePlacesSearchService).to receive(:get_business_details)
        .with(place_id)
        .and_return(business_details)

      get :google_business_details, params: { place_id: place_id }, format: :json
    end

    context 'when place_id is blank' do
      it 'returns bad request error' do
        get :google_business_details, params: { place_id: '' }, format: :json

        expect(response).to have_http_status(:bad_request)
        expect(json_response['error']).to eq('Place ID is required')
      end
    end

    context 'when service returns error' do
      before do
        allow(GooglePlacesSearchService).to receive(:get_business_details)
          .and_return({ error: 'Invalid place ID' })
      end

      it 'returns the service error' do
        get :google_business_details, params: { place_id: place_id }, format: :json

        expect(response).to have_http_status(:success)
        expect(json_response['error']).to eq('Invalid place ID')
      end
    end

    context 'when an exception occurs' do
      before do
        allow(GooglePlacesSearchService).to receive(:get_business_details)
          .and_raise(StandardError.new('Service error'))
        allow(Rails.logger).to receive(:error)
      end

      it 'returns internal server error' do
        get :google_business_details, params: { place_id: place_id }, format: :json

        expect(response).to have_http_status(:internal_server_error)
        expect(json_response['error']).to eq('Failed to fetch business details')
        expect(Rails.logger).to have_received(:error)
          .with(match(/Google Business details error.*Service error/))
      end
    end
  end

  describe 'POST #google_business_connect' do
    let(:place_id) { 'ChIJN1t_tDeuEmsRUsoyG83frY4' }
    let(:business_name) { 'Test Business' }
    let(:business_details) do
      {
        success: true,
        business: {
          place_id: place_id,
          name: business_name,
          address: '123 Main St, New York, NY, USA'
        }
      }
    end

    before do
      allow(GooglePlacesSearchService).to receive(:get_business_details).and_return(business_details)
      allow(GoogleBusinessVerificationService).to receive(:verify_match).and_return({ ok: true })
    end

    it 'connects business to Google Place ID' do
      expect {
        post :google_business_connect, params: { place_id: place_id, business_name: business_name }, format: :json
      }.to change { business.reload.google_place_id }.to(place_id)

      expect(response).to have_http_status(:success)
      expect(json_response['success']).to be true
      expect(json_response['message']).to eq('Google Business successfully connected!')
    end

    it 'verifies place_id before connecting' do
      expect(GooglePlacesSearchService).to receive(:get_business_details)
        .with(place_id)
        .and_return(business_details)

      post :google_business_connect, params: { place_id: place_id, business_name: business_name }, format: :json
    end

    it 'logs the connection' do
      allow(Rails.logger).to receive(:info).and_call_original
      expect(Rails.logger).to receive(:info)
        .with(match(/Connected business #{business.id} to Google Place ID: #{place_id}/))
        .and_call_original

      post :google_business_connect, params: { place_id: place_id, business_name: business_name }, format: :json
    end

    context 'when place_id is blank' do
      it 'returns bad request error' do
        post :google_business_connect, params: { place_id: '', business_name: business_name }, format: :json

        expect(response).to have_http_status(:bad_request)
        expect(json_response['error']).to eq('Place ID is required')
      end
    end

    context 'when verification fails' do
      before do
        allow(GooglePlacesSearchService).to receive(:get_business_details)
          .and_return({ error: 'Invalid place ID' })
      end

      it 'returns bad request error' do
        post :google_business_connect, params: { place_id: place_id, business_name: business_name }, format: :json

        expect(response).to have_http_status(:bad_request)
        expect(json_response['error']).to eq('Invalid place ID')
      end

      it 'does not update business' do
        expect {
          post :google_business_connect, params: { place_id: place_id, business_name: business_name }, format: :json
        }.not_to change { business.reload.google_place_id }
      end
    end

    context 'when business update fails' do
      before do
        allow_any_instance_of(Business).to receive(:update).and_return(false)
        allow_any_instance_of(Business).to receive(:errors).and_return(
          double(full_messages: ['Validation failed'])
        )
        allow(GoogleBusinessVerificationService).to receive(:verify_match).and_return({ ok: true })
      end

      it 'returns unprocessable entity error' do
        post :google_business_connect, params: { place_id: place_id, business_name: business_name }, format: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json_response['error']).to eq('Failed to save Google Business connection')
        expect(json_response['details']).to eq(['Validation failed'])
      end
    end

    context 'when an exception occurs' do
      before do
        allow(GooglePlacesSearchService).to receive(:get_business_details)
          .and_raise(StandardError.new('Service error'))
        allow(Rails.logger).to receive(:error)
      end

      it 'returns internal server error' do
        post :google_business_connect, params: { place_id: place_id, business_name: business_name }, format: :json

        expect(response).to have_http_status(:internal_server_error)
        expect(json_response['error']).to eq('Connection failed')
        expect(Rails.logger).to have_received(:error)
          .with(match(/Google Business connect error.*Service error/))
      end
    end
  end

  describe 'DELETE #google_business_disconnect' do
    let(:place_id) { 'ChIJN1t_tDeuEmsRUsoyG83frY4' }

    before do
      business.update!(google_place_id: place_id)
    end

    it 'disconnects business from Google Place ID' do
      expect {
        delete :google_business_disconnect, format: :json
      }.to change { business.reload.google_place_id }.to(nil)

      expect(response).to have_http_status(:success)
      expect(json_response['success']).to be true
      expect(json_response['message']).to eq('Google Business successfully disconnected')
    end

    it 'logs the disconnection' do
      allow(Rails.logger).to receive(:info).and_call_original
      expect(Rails.logger).to receive(:info)
        .with(match(/Disconnected business #{business.id} from Google Place ID: #{place_id}/))
        .and_call_original

      delete :google_business_disconnect, format: :json
    end

    context 'when business update fails' do
      before do
        allow_any_instance_of(Business).to receive(:update).and_return(false)
        allow_any_instance_of(Business).to receive(:errors).and_return(
          double(full_messages: ['Validation failed'])
        )
      end

      it 'returns unprocessable entity error' do
        delete :google_business_disconnect, format: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json_response['error']).to eq('Failed to disconnect Google Business')
        expect(json_response['details']).to eq(['Validation failed'])
      end
    end

    context 'when an exception occurs' do
      before do
        allow_any_instance_of(Business).to receive(:update)
          .and_raise(StandardError.new('Database error'))
        allow(Rails.logger).to receive(:error)
      end

      it 'returns internal server error' do
        delete :google_business_disconnect, format: :json

        expect(response).to have_http_status(:internal_server_error)
        expect(json_response['error']).to eq('Disconnection failed')
        expect(Rails.logger).to have_received(:error)
          .with(match(/Google Business disconnect error.*Database error/))
      end
    end
  end

  describe 'GET #google_business_status' do
    context 'when business has google_place_id' do
      let(:place_id) { 'ChIJN1t_tDeuEmsRUsoyG83frY4' }
      let(:business_details) do
        {
          success: true,
          business: {
            place_id: place_id,
            name: 'Test Business',
            address: '123 Main St, New York, NY, USA'
          }
        }
      end

      before do
        business.update!(google_place_id: place_id)
        allow(GooglePlacesSearchService).to receive(:get_business_details).and_return(business_details)
      end

      it 'returns connected status with business details' do
        get :google_business_status, format: :json

        expect(response).to have_http_status(:success)
        expect(json_response['connected']).to be true
        expect(json_response['place_id']).to eq(place_id)
        expect(json_response['business']['name']).to eq('Test Business')
      end

      context 'when verification fails' do
        before do
          allow(GooglePlacesSearchService).to receive(:get_business_details)
            .and_return({ error: 'Invalid place ID' })
        end

        it 'returns connected status with warning' do
          get :google_business_status, format: :json

          expect(response).to have_http_status(:success)
          expect(json_response['connected']).to be true
          expect(json_response['place_id']).to eq(place_id)
          expect(json_response['warning']).to be_present
          expect(json_response['error']).to eq('Unable to verify Google Business connection')
        end
      end
    end

    context 'when business has no google_place_id' do
      it 'returns disconnected status' do
        get :google_business_status, format: :json

        expect(response).to have_http_status(:success)
        expect(json_response['connected']).to be false
      end
    end

    context 'when an exception occurs' do
      before do
        business.update!(google_place_id: 'test_id')
        allow(GooglePlacesSearchService).to receive(:get_business_details)
          .and_raise(StandardError.new('Service error'))
        allow(Rails.logger).to receive(:error)
      end

      it 'returns connection status with error' do
        get :google_business_status, format: :json

        expect(response).to have_http_status(:success)
        expect(json_response['connected']).to be true
        expect(json_response['place_id']).to eq('test_id')
        expect(json_response['error']).to eq('Unable to check connection status')
        expect(Rails.logger).to have_received(:error)
          .with(match(/Google Business status error.*Service error/))
      end
    end
  end

  describe '#google_business_oauth_callback_url (private method)' do
    let(:integrations_controller) { described_class.new }

    before do
      # Set up request object mock for the controller
      allow(integrations_controller).to receive(:request).and_return(request)
    end

    context 'when main_domain is configured' do
      before do
        allow(Rails.application.config).to receive(:main_domain).and_return('example.com')
      end

      it 'uses main_domain for URL generation' do
        allow(request).to receive(:ssl?).and_return(false)
        allow(request).to receive(:port).and_return(3000)

        url = integrations_controller.send(:google_business_oauth_callback_url)

        expect(url).to eq('http://example.com:3000/oauth/google-business/callback')
      end

      it 'uses https when request is SSL' do
        allow(request).to receive(:ssl?).and_return(true)
        allow(request).to receive(:port).and_return(443)

        url = integrations_controller.send(:google_business_oauth_callback_url)

        expect(url).to eq('https://example.com/oauth/google-business/callback')
      end

      it 'excludes port for standard SSL port' do
        allow(request).to receive(:ssl?).and_return(true)
        allow(request).to receive(:port).and_return(443)

        url = integrations_controller.send(:google_business_oauth_callback_url)

        expect(url).to eq('https://example.com/oauth/google-business/callback')
      end

      it 'excludes port for standard HTTP port' do
        allow(request).to receive(:ssl?).and_return(false)
        allow(request).to receive(:port).and_return(80)

        url = integrations_controller.send(:google_business_oauth_callback_url)

        expect(url).to eq('http://example.com/oauth/google-business/callback')
      end

      it 'handles main_domain that already includes port' do
        allow(Rails.application.config).to receive(:main_domain).and_return('example.com:8080')
        allow(request).to receive(:ssl?).and_return(false)
        allow(request).to receive(:port).and_return(3000)

        url = integrations_controller.send(:google_business_oauth_callback_url)

        expect(url).to eq('http://example.com:8080/oauth/google-business/callback')
      end
    end

    context 'when main_domain is nil' do
      before do
        allow(Rails.application.config).to receive(:main_domain).and_return(nil)
        allow(request).to receive(:host).and_return('localhost')
      end

      it 'falls back to request.host' do
        allow(request).to receive(:ssl?).and_return(false)
        allow(request).to receive(:port).and_return(3000)

        url = integrations_controller.send(:google_business_oauth_callback_url)

        expect(url).to eq('http://localhost:3000/oauth/google-business/callback')
      end

      it 'handles nil request.port gracefully' do
        allow(request).to receive(:ssl?).and_return(false)
        allow(request).to receive(:port).and_return(nil)

        url = integrations_controller.send(:google_business_oauth_callback_url)

        expect(url).to eq('http://localhost/oauth/google-business/callback')
      end
    end

    context 'edge cases' do
      before do
        allow(Rails.application.config).to receive(:main_domain).and_return('')
        allow(request).to receive(:host).and_return('fallback.com')
      end

      it 'handles empty string main_domain by falling back to request.host' do
        allow(request).to receive(:ssl?).and_return(true)
        allow(request).to receive(:port).and_return(443)

        url = integrations_controller.send(:google_business_oauth_callback_url)

        expect(url).to eq('https://fallback.com/oauth/google-business/callback')
      end
    end
  end

  private

  def json_response
    JSON.parse(response.body)
  end
end