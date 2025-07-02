require 'rails_helper'

RSpec.describe Public::ReferralController, type: :controller do
  let(:business) { create(:business, referral_program_enabled: true) }
  let(:client_user) { create(:user, role: :client) }
  let(:manager_user) { create(:user, role: :manager, business: business) }

  before do
    business.save! unless business.persisted?
    ActsAsTenant.current_tenant = business
    @request.host = 'testbiz.lvh.me'
    
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

  describe 'GET #show' do
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
        get :show
        expect(response).to have_http_status(:success)
        expect(assigns(:business)).to eq(business)
        expect(assigns(:referral_code)).to be_present
      end

      it 'generates a referral code for the user' do
        allow(ReferralService).to receive(:generate_referral_code).with(client_user, business).and_return('TEST123')
        referrals_relation = double('referrals_relation')
        allow(referrals_relation).to receive(:where).and_return(referrals_relation)
        allow(referrals_relation).to receive(:includes).and_return([])
        allow(referrals_relation).to receive(:count).and_return(0)
        allow(referrals_relation).to receive(:qualified).and_return(referrals_relation)
        allow(referrals_relation).to receive(:pending).and_return(referrals_relation)
        allow(client_user).to receive(:referrals_made).and_return(referrals_relation)
        get :show
        expect(assigns(:referral_code)).to eq('TEST123')
      end
    end

    context 'when user is a business manager' do
      before { sign_in manager_user }

      it 'shows the referral program in preview mode with flash message' do
        get :show
        expect(response).to have_http_status(:success)
        expect(flash[:alert]).to eq('Referral program is only available for client users')
        expect(assigns(:business)).to eq(business)
        expect(assigns(:referral_code)).to be_nil
        expect(assigns(:referral_url)).to be_nil
        expect(assigns(:my_referrals)).to eq([])
        expect(assigns(:referral_stats)).to be_nil
      end
    end

    context 'when user is not signed in' do
      it 'redirects to sign in page' do
        get :show
        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:alert]).to eq('You need to sign in or sign up before continuing.')
      end
    end

    context 'when referral program is disabled' do
      before do
        business.update!(referral_program_enabled: false)
        sign_in client_user
      end

      it 'redirects with an error message' do
        get :show
        expect(response).to redirect_to(tenant_root_path)
        expect(flash[:alert]).to eq('Referral program is not available for this business')
      end
    end
  end
end 