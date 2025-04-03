# frozen_string_literal: true

require 'rails_helper'

RSpec.describe HomeController, type: :controller do
  # Include Devise test helpers
  include Devise::Test::ControllerHelpers
  
  describe 'GET #index' do
    it 'returns a successful response' do
      get :index
      expect(response).to have_http_status(:success)
    end
  end
end 