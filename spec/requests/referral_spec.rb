require 'rails_helper'

RSpec.describe '/referral', type: :request do
  let(:business) { create(:business, referral_program_enabled: true) }
  let(:client_user) { create(:user, role: :client) }
  let(:manager_user) { create(:user, role: :manager, business: business) }

  before do
    host! "#{business.subdomain}.example.com"
    ActsAsTenant.current_tenant = business
    
    business.create_referral_program!(
      active: true,
      referrer_reward_type: 'points',
      referrer_reward_value: 100,
      referral_code_discount_amount: 10.0,
      min_purchase_amount: 0.0
    )
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe 'GET /referral' do
    context 'when user is a client' do
      before { sign_in client_user }

      it 'renders the referral program page' do
        allow(ReferralService).to receive(:generate_referral_code).with(client_user, business).and_return('TEST123')
        referrals_relation = double('referrals_relation')
        allow(referrals_relation).to receive(:where).and_return(referrals_relation)
        allow(referrals_relation).to receive(:includes).and_return([])
        allow(referrals_relation).to receive(:count).and_return(0)
        allow(referrals_relation).to receive(:qualified).and_return(referrals_relation)
        allow(referrals_relation).to receive(:pending).and_return(referrals_relation)
        allow(client_user).to receive(:referrals_made).and_return(referrals_relation)
        get '/referral'
        expect(response).to have_http_status(:success)
        expect(response.body).to include("Your Unique Referral Code")
        expect(response.body).to include("TEST123")
      end

      it 'displays the referral program benefits' do
        allow(ReferralService).to receive(:generate_referral_code).with(client_user, business).and_return('TEST123')
        referrals_relation = double('referrals_relation')
        allow(referrals_relation).to receive(:where).and_return(referrals_relation)
        allow(referrals_relation).to receive(:includes).and_return([])
        allow(referrals_relation).to receive(:count).and_return(0)
        allow(referrals_relation).to receive(:qualified).and_return(referrals_relation)
        allow(referrals_relation).to receive(:pending).and_return(referrals_relation)
        allow(client_user).to receive(:referrals_made).and_return(referrals_relation)
        get '/referral'
        expect(response).to have_http_status(:success)
        expect(response.body).to include("100")
        expect(response.body).to include("Points")
        expect(response.body).to include("$10 off")
      end
    end

    context 'when user is a business manager' do
      before { sign_in manager_user }

      it 'shows preview mode with flash message for business users' do
        get '/referral'
        expect(response).to have_http_status(:success)
        expect(response.body).to include('Referral program is only available for client users')
        expect(response.body).to include('Referral Program Preview')
        expect(response.body).to include('This is how customer referral codes will appear')
        expect(response.body).to include('ABC123XYZ')
      end
    end

    context 'when user is not signed in' do
      it 'redirects to sign in page' do
        get '/referral'
        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context 'when referral program is disabled' do
      before do
        business.update!(referral_program_enabled: false)
        sign_in client_user
      end

      it 'redirects to business page with error' do
        get '/referral'
        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(tenant_root_path)
        follow_redirect!
        expect(response.body).to include('Referral program is not available for this business')
      end
    end
  end
end 