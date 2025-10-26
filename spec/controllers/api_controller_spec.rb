# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApiController, type: :controller do
  # Create an anonymous controller for testing the base ApiController
  controller(ApiController) do
    def index
      render json: { status: 'ok', message: 'API endpoint working' }
    end

    def create
      render json: { status: 'created', data: params[:data] }, status: :created
    end
  end

  before do
    # Define routes for the anonymous controller
    routes.draw do
      get 'index' => 'api#index'
      post 'create' => 'api#create'
    end
  end

  describe 'CSRF protection' do
    it 'does not include RequestForgeryProtection module' do
      expect(controller.class.ancestors).not_to include(ActionController::RequestForgeryProtection)
    end

    it 'does not include protect_from_forgery callback' do
      callbacks = controller.class._process_action_callbacks.select do |callback|
        callback.filter.to_s.include?('verify_authenticity_token')
      end
      expect(callbacks).to be_empty
    end

    it 'allows POST requests without CSRF token' do
      post :create, format: :json, params: { data: 'test' }
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json['status']).to eq('created')
    end
  end

  describe 'format enforcement' do
    it 'accepts JSON requests' do
      get :index, format: :json
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include('application/json')
    end

    it 'rejects HTML requests' do
      get :index, format: :html
      expect(response).to have_http_status(:not_acceptable)
    end

    it 'rejects XML requests' do
      get :index, format: :xml
      expect(response).to have_http_status(:not_acceptable)
    end

    it 'defaults to JSON for wildcard Accept header' do
      request.headers['Accept'] = '*/*'
      get :index
      expect(response).to have_http_status(:ok)
      expect(request.format.json?).to be true
    end

    it 'accepts requests with explicit JSON format' do
      get :index, format: :json
      expect(request.format.json?).to be true
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include('application/json')
    end
  end

  describe 'API inheritance' do
    it 'inherits from ActionController::API' do
      expect(ApiController.ancestors).to include(ActionController::API)
    end

    it 'does not inherit from ActionController::Base' do
      expect(ApiController.ancestors).not_to include(ActionController::Base)
    end

    it 'does not include view rendering modules' do
      # ActionController::API excludes many modules that Base includes
      expect(controller.class.ancestors).not_to include(ActionView::Layouts)
    end
  end

  describe 'JSON responses' do
    it 'returns valid JSON for successful requests' do
      get :index, format: :json
      expect { JSON.parse(response.body) }.not_to raise_error
      json = JSON.parse(response.body)
      expect(json).to be_a(Hash)
      expect(json['status']).to eq('ok')
    end

    it 'handles POST requests with JSON params' do
      post :create, format: :json, params: { data: { key: 'value' } }
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json['data']).to be_present
    end
  end

  describe 'security characteristics' do
    it 'does not set session cookies' do
      get :index, format: :json
      expect(response.cookies['_session_id']).to be_nil
    end

    it 'does not require authenticity token' do
      # This would raise ActionController::InvalidAuthenticityToken with ApplicationController
      expect {
        post :create, format: :json, params: { data: 'test' }
      }.not_to raise_error
    end

    it 'responds with 406 Not Acceptable for wrong content type (prevents content-type confusion)' do
      get :index, format: :html
      expect(response.status).to eq(406)
    end
  end
end
