require 'rails_helper'

RSpec.describe "Users::SessionsController cross-domain redirects", type: :request do
  let(:business) { create(:business, :with_custom_domain, hostname: 'newcoworker.test') }
  let(:manager)  { create(:user, :manager, business: business) }

  before do
    host! 'www.example.com'
  end

  it "redirects already authenticated users to their tenant domain without triggering unsafe redirect" do
    sign_in manager

    expect do
      get new_user_session_path
    end.not_to raise_error

    current_request   = response.request
    expected_location = TenantHost.url_for(business, current_request, '/manage/dashboard')

    expect(response).to have_http_status(Devise::Controllers::Responder.redirect_status)
    expect(response.headers['Location']).to eq(expected_location)
    expect(flash[:alert]).to eq(I18n.t('devise.failure.already_authenticated'))
  end
end

