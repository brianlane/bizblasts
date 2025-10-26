# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Health Checks', type: :request do
  describe 'GET /healthcheck' do
    it 'returns a successful response' do
      get health_check_path, headers: { 'Accept' => 'application/json' }
      expect(response).to have_http_status(:success)
    end

    it 'returns JSON with status ok' do
      get health_check_path, headers: { 'Accept' => 'application/json' }
      json_response = JSON.parse(response.body)
      expect(json_response['status']).to eq('ok')
    end

    it 'rejects non-JSON requests' do
      get health_check_path, headers: { 'Accept' => 'text/html' }
      expect(response).to have_http_status(:not_acceptable)
    end
  end

  describe 'GET /up' do
    it 'returns a successful response for the Rails health check' do
      get rails_health_check_path
      expect(response).to have_http_status(:success)
    end
  end

  describe 'GET /db-check' do
    it 'returns a successful response when database is connected' do
      allow(ActiveRecord::Base.connection).to receive(:execute).and_return([{"?column?"=>1}])

      get db_check_path, headers: { 'Accept' => 'application/json' }
      expect(response).to have_http_status(:success)
    end

    it 'returns appropriate error when database connection fails', :no_db_clean => true do
      allow(ActiveRecord::Base.connection).to receive(:execute).and_raise(ActiveRecord::ConnectionNotEstablished)

      get db_check_path, headers: { 'Accept' => 'application/json' }
      expect(response).to have_http_status(:service_unavailable)
    end
  end
end 