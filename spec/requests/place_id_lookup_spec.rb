# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Place ID Lookup - Async Extraction', type: :request do
  let(:business) { create(:business) }
  let(:user) { create(:user, :manager, business: business) }

  before do
    # Set up multi-tenant context
    host! "#{business.hostname}.lvh.me"
    ActsAsTenant.current_tenant = business
    sign_in user
    
    # Clear rate limit cache for this user to prevent 429 errors
    Rails.cache.delete("place_id_extraction:user:#{user.id}")
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe 'POST /manage/settings/integrations/lookup-place-id' do
    let(:google_maps_url) { 'https://www.google.com/maps/place/Losne+Massage/@33.5371998,-112.2300583' }

    context 'when input is valid' do
      it 'starts async job and returns job ID' do
        post lookup_place_id_business_manager_settings_integrations_path, params: { input: google_maps_url }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['job_id']).to be_present
        expect(json['message']).to include('Extraction started')
      end

      it 'queues PlaceIdExtractionJob' do
        expect {
          post lookup_place_id_business_manager_settings_integrations_path, params: { input: google_maps_url }
        }.to have_enqueued_job(PlaceIdExtractionJob)
      end
    end

    context 'when input is invalid' do
      it 'returns error for blank input' do
        post lookup_place_id_business_manager_settings_integrations_path, params: { input: '' }

        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['error']).to include('Please enter a Google Maps URL')
      end

      it 'returns error when not a Google Maps URL' do
        post lookup_place_id_business_manager_settings_integrations_path, params: { input: 'https://example.com' }

        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['error']).to include('valid Google Maps URL')
      end
    end

    context 'authorization' do
      it 'requires authentication' do
        sign_out user
        post lookup_place_id_business_manager_settings_integrations_path, params: { input: google_maps_url }

        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'GET /manage/settings/integrations/check-place-id-status/:job_id' do
    let(:job_id) { SecureRandom.uuid }

    context 'when job is processing' do
      before do
        Rails.cache.write("place_id_extraction:#{job_id}", {
          status: 'processing',
          message: 'Loading Google Maps...',
          updated_at: Time.current.to_i
        })
      end

      it 'returns processing status' do
        get "/manage/settings/integrations/check-place-id-status/#{job_id}"

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['status']).to eq('processing')
        expect(json['message']).to be_present
      end
    end

    context 'when job is completed' do
      let(:place_id) { 'ChIJN1t_tDeuEmsRUsoyG83frY4' }

      before do
        Rails.cache.write("place_id_extraction:#{job_id}", {
          status: 'completed',
          place_id: place_id,
          message: 'Place ID found',
          updated_at: Time.current.to_i
        })
      end

      it 'returns completed status with Place ID' do
        get "/manage/settings/integrations/check-place-id-status/#{job_id}"

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['status']).to eq('completed')
        expect(json['place_id']).to eq(place_id)
      end
    end

    context 'when job failed' do
      before do
        Rails.cache.write("place_id_extraction:#{job_id}", {
          status: 'failed',
          error: 'Could not find Place ID',
          updated_at: Time.current.to_i
        })
      end

      it 'returns failed status with error' do
        get "/manage/settings/integrations/check-place-id-status/#{job_id}"

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['status']).to eq('failed')
        expect(json['error']).to be_present
      end
    end

    context 'when job not found' do
      it 'returns not found error' do
        get "/manage/settings/integrations/check-place-id-status/invalid-job-id"

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['status']).to eq('not_found')
      end
    end

    context 'when job_id is blank' do
      it 'returns bad request' do
        get "/manage/settings/integrations/check-place-id-status/"

        expect(response).to have_http_status(:not_found) # Rails routing will return 404
      end
    end

    context 'authorization' do
      it 'requires authentication' do
        sign_out user
        get "/manage/settings/integrations/check-place-id-status/#{job_id}"

        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end
