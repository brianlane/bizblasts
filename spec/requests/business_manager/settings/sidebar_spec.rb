require 'rails_helper'
require 'devise/test/integration_helpers'

RSpec.describe BusinessManager::Settings::SidebarController, type: :request do
  include Devise::Test::IntegrationHelpers

  let!(:business) { create(:business) }
  let!(:manager) { create(:user, :manager, business: business) }
  let!(:staff) { create(:user, :staff, business: business) }
  let!(:client) { create(:user, :client) }
  let(:host_name) { "#{business.hostname}.lvh.me" }

  before do
    host! host_name
    ActsAsTenant.current_tenant = business
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe 'GET /manage/settings/sidebar/edit_sidebar' do
    subject { get edit_sidebar_business_manager_settings_sidebar_path }

    context 'when authenticated as manager' do
      before { sign_in manager }
      it 'renders the edit sidebar page' do
        subject
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('Customize Sidebar')
      end
    end

    context 'when authenticated as staff' do
      before { sign_in staff }
      it 'renders the edit sidebar page' do
        subject
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('Customize Sidebar')
      end
    end

    context 'when authenticated as client' do
      before { sign_in client }
      it 'redirects to root or denies access' do
        subject
        expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
      end
    end

    context 'when unauthenticated' do
      it 'redirects to sign in' do
        subject
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'PATCH /manage/settings/sidebar/update_sidebar' do
    let(:sidebar_params) do
      [
        { key: 'dashboard', visible: '1' },
        { key: 'bookings', visible: '0' }
      ]
    end

    subject do
      patch update_sidebar_business_manager_settings_sidebar_path, params: { sidebar_items: sidebar_params }
    end

    context 'when authenticated as manager' do
      before { sign_in manager }
      it 'updates sidebar and redirects' do
        subject
        expect(response).to redirect_to(edit_sidebar_business_manager_settings_sidebar_path)
        manager.reload
        expect(manager.user_sidebar_items.find_by(item_key: 'dashboard').visible).to eq(true)
        expect(manager.user_sidebar_items.find_by(item_key: 'bookings').visible).to eq(false)
      end
    end

    context 'when authenticated as staff' do
      before { sign_in staff }
      it 'updates sidebar and redirects' do
        subject
        expect(response).to redirect_to(edit_sidebar_business_manager_settings_sidebar_path)
        staff.reload
        expect(staff.user_sidebar_items.find_by(item_key: 'dashboard').visible).to eq(true)
        expect(staff.user_sidebar_items.find_by(item_key: 'bookings').visible).to eq(false)
      end
    end

    context 'when authenticated as client' do
      before { sign_in client }
      it 'redirects to root or denies access' do
        subject
        expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
      end
    end

    context 'when unauthenticated' do
      it 'redirects to sign in' do
        subject
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end 