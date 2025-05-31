# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PolicyAcceptancesController, type: :controller do
  let(:user) { create(:user) }
  let!(:privacy_policy) { create(:policy_version, policy_type: 'privacy_policy', version: 'v1.0', active: true) }
  let!(:terms_policy) { create(:policy_version, policy_type: 'terms_of_service', version: 'v1.0', active: true) }
  
  before do
    sign_in user
  end
  
  describe 'GET #status' do
    context 'when user needs policy acceptance' do
      before do
        user.update!(requires_policy_acceptance: true)
      end
      
      it 'returns policy status with missing policies' do
        get :status, format: :json
        
        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        
        expect(json_response['requires_policy_acceptance']).to be true
        expect(json_response['missing_policies']).to be_an(Array)
        expect(json_response['missing_policies'].length).to be > 0
      end
      
      it 'includes policy details in response' do
        get :status, format: :json
        
        json_response = JSON.parse(response.body)
        missing_policy = json_response['missing_policies'].first
        
        expect(missing_policy).to have_key('policy_type')
        expect(missing_policy).to have_key('policy_name')
        expect(missing_policy).to have_key('policy_path')
        expect(missing_policy).to have_key('version')
      end
    end
    
    context 'when user does not need policy acceptance' do
      before do
        # Create acceptances for all required policies
        create(:policy_acceptance, user: user, policy_type: 'privacy_policy', policy_version: 'v1.0')
        create(:policy_acceptance, user: user, policy_type: 'terms_of_service', policy_version: 'v1.0')
        create(:policy_acceptance, user: user, policy_type: 'acceptable_use_policy', policy_version: 'v1.0')
      end
      
      it 'returns false for requires_policy_acceptance' do
        get :status, format: :json
        
        json_response = JSON.parse(response.body)
        expect(json_response['requires_policy_acceptance']).to be false
        expect(json_response['missing_policies']).to be_empty
      end
    end
  end
  
  describe 'POST #create' do
    let(:valid_params) do
      {
        policy_type: 'privacy_policy',
        version: 'v1.0'
      }
    end
    
    context 'with valid parameters' do
      it 'creates a policy acceptance record' do
        expect {
          post :create, params: valid_params, format: :json
        }.to change(PolicyAcceptance, :count).by(1)
      end
      
      it 'returns success response' do
        post :create, params: valid_params, format: :json
        
        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be true
      end
      
      it 'records the acceptance with correct attributes' do
        post :create, params: valid_params, format: :json
        
        acceptance = PolicyAcceptance.last
        expect(acceptance.user).to eq(user)
        expect(acceptance.policy_type).to eq('privacy_policy')
        expect(acceptance.policy_version).to eq('v1.0')
      end
    end
    
    context 'with invalid version' do
      let(:invalid_params) do
        {
          policy_type: 'privacy_policy',
          version: 'v2.0' # Non-existent version
        }
      end
      
      it 'returns error response' do
        post :create, params: invalid_params, format: :json
        
        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be false
        expect(json_response['error']).to eq('Invalid policy version')
      end
    end
  end
  
  describe 'POST #bulk_create' do
    let(:valid_params) do
      {
        policy_acceptances: {
          'privacy_policy' => '1',
          'terms_of_service' => '1'
        }
      }
    end
    
    context 'with valid parameters' do
      it 'creates multiple policy acceptance records' do
        expect {
          post :bulk_create, params: valid_params, format: :json
        }.to change(PolicyAcceptance, :count).by(2)
      end
      
      it 'returns success response' do
        post :bulk_create, params: valid_params, format: :json
        
        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be true
      end
      
      it 'marks user policies as accepted when all required policies are accepted' do
        # Create AUP version for client user
        create(:policy_version, policy_type: 'acceptable_use_policy', version: 'v1.0', active: true)
        
        bulk_params = {
          policy_acceptances: {
            'privacy_policy' => '1',
            'terms_of_service' => '1',
            'acceptable_use_policy' => '1'
          }
        }
        
        user.update!(requires_policy_acceptance: true)
        
        expect {
          post :bulk_create, params: bulk_params, format: :json
        }.to change { user.reload.requires_policy_acceptance }.from(true).to(false)
      end
    end
    
    context 'with partial acceptance' do
      let(:partial_params) do
        {
          policy_acceptances: {
            'privacy_policy' => '1',
            'terms_of_service' => '0' # Not accepted
          }
        }
      end
      
      it 'only creates acceptance for accepted policies' do
        expect {
          post :bulk_create, params: partial_params, format: :json
        }.to change(PolicyAcceptance, :count).by(1)
        
        expect(PolicyAcceptance.last.policy_type).to eq('privacy_policy')
      end
    end
    
    context 'when policy version does not exist' do
      before do
        privacy_policy.destroy
      end
      
      it 'returns error response' do
        post :bulk_create, params: valid_params, format: :json
        
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be false
        expect(json_response['errors']).to include('No current version for privacy_policy')
      end
    end
  end
  
  context 'when user is not authenticated' do
    before do
      sign_out user
    end
    
    it 'redirects to sign in for status' do
      get :status, format: :json
      expect(response).to have_http_status(:unauthorized)
    end
    
    it 'redirects to sign in for create' do
      post :create, params: { policy_type: 'privacy_policy', version: 'v1.0' }, format: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end
end 