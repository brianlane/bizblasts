# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BusinessManager::AnalyticsController, type: :controller do
  let(:business) { create(:business) }
  let(:user) { create(:user, :manager, business: business) }

  before do
    # Set the request host to match the business tenant subdomain
    @request.host = "#{business.hostname}.lvh.me"
    ActsAsTenant.current_tenant = business
    sign_in user
  end

  describe 'GET #index' do
    it 'returns success' do
      get :index
      expect(response).to be_successful
    end

    it 'sets default period to last_30_days' do
      get :index
      expect(assigns(:period)).to eq(:last_30_days)
    end

    it 'accepts custom period parameter' do
      get :index, params: { period: 'last_7_days' }
      expect(assigns(:period)).to eq(:last_7_days)
    end

    it 'loads overview metrics' do
      get :index
      expect(assigns(:overview)).to be_present
      expect(assigns(:quick_stats)).to be_present
    end
  end

  describe 'GET #traffic' do
    before do
      create_list(:visitor_session, 10, business: business)
      create_list(:page_view, 20, business: business)
    end

    it 'returns traffic analytics' do
      get :traffic
      expect(response).to be_successful
      expect(assigns(:overview)).to be_present
    end
  end

  describe 'GET #export' do
    it 'shows export options' do
      get :export
      expect(response).to be_successful
      expect(assigns(:export_types)).to be_present
    end
  end

  describe 'POST #perform_export' do
    let(:export_params) do
      {
        export_type: 'page_views',
        format_type: 'csv',
        start_date: 30.days.ago.to_date.to_s,
        end_date: Date.current.to_s
      }
    end

    it 'generates CSV export' do
      post :perform_export, params: export_params
      expect(response.header['Content-Type']).to include('text/csv')
      expect(response.header['Content-Disposition']).to include('attachment')
    end

    it 'handles invalid export type' do
      post :perform_export, params: export_params.merge(export_type: 'invalid')
      expect(response).to redirect_to(business_manager_export_analytics_path)
      expect(flash[:alert]).to be_present
    end
  end
end
