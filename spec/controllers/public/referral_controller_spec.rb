require 'rails_helper'

RSpec.describe Public::ReferralController, type: :controller do
  let(:business) { create(:business) }
  let(:user) { create(:user, role: :client) }
  let(:tenant_customer) { create(:tenant_customer, business: business, email: user.email) }

  before do
    ActsAsTenant.current_tenant = business
    business.update!(referral_program_enabled: true)
    business.create_referral_program!(
      active: true,
      referrer_reward_type: 'points',
      referrer_reward_value: 100,
      referral_code_discount_amount: 10.0,
      min_purchase_amount: 0.0
    )
    request.host = "#{business.hostname}.lvh.me"
  end

  describe 'GET #show' do
    before { sign_in user }

    context 'when customer has referral code' do
      let!(:referral) { create(:referral, 
                              business: business, 
                              referrer: user,
                              referred_tenant_customer: tenant_customer,
                              referral_code: 'TEST123') }

      it 'displays referral code' do
        get :show
        
        expect(response).to have_http_status(:success)
        expect(assigns(:referral_code)).to eq('TEST123')
        expect(assigns(:referral_stats)).to be_present
        expect(assigns(:referral_url)).to include('TEST123')
      end
    end

    context 'when customer has no referral code' do
      it 'creates new referral code' do
        expect {
          get :show
        }.to change { Referral.count }.by(1)

        expect(response).to have_http_status(:success)
        expect(assigns(:referral_code)).to be_present
        
        referral = Referral.last
        expect(referral.referrer).to eq(user)
        expect(referral.business).to eq(business)
      end
    end

    context 'when user is not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        get :show
        
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context 'when referral program is disabled' do
      before do
        business.update!(referral_program_enabled: false)
      end

      it 'redirects with error message' do
        get :show
        
        expect(response).to redirect_to(tenant_root_path)
        expect(flash[:alert]).to include('not available')
      end
    end

    context 'when user is not a client' do
      let(:manager_user) { create(:user, role: :manager, business: business) }
      
      before do
        sign_out user
        sign_in manager_user
      end

      it 'shows warning message for non-client users' do
        get :show
        
        expect(response).to have_http_status(:success)
        expect(flash.now[:alert]).to include('only available for client users')
        expect(assigns(:referral_code)).to be_nil
      end
    end
  end

  describe 'GET #index' do
    before { sign_in user }

    context 'cross-business referral overview' do
      let(:other_business) { create(:business, hostname: 'otherbiz') }
      let!(:referral1) { create(:referral, business: business, referrer: user) }
      let!(:referral2) { create(:referral, business: other_business, referrer: user) }

      it 'shows referrals across all businesses' do
        get :index
        
        expect(response).to have_http_status(:success)
        expect(assigns(:referrals_by_business)).to be_present
        expect(assigns(:referral_stats)).to be_present
        expect(assigns(:referral_stats)[:total_referrals]).to eq(2)
      end
    end

    context 'when user is not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        get :index
        
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'private methods' do
    let(:controller_instance) { described_class.new }
    
    before do
      ActsAsTenant.current_tenant = business
    end

    describe '#set_business' do
      it 'finds business from current tenant' do
        controller_instance.send(:set_business)
        expect(controller_instance.instance_variable_get(:@business)).to eq(business)
      end

      it 'raises error when no current tenant' do
        ActsAsTenant.current_tenant = nil
        
        expect {
          controller_instance.send(:set_business)
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    describe '#generate_referral_url' do
      it 'generates correct URL for development' do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
        
        url = controller_instance.send(:generate_referral_url, business, 'TEST123')
        expect(url).to eq("http://#{business.hostname}.lvh.me:3000?ref=TEST123")
      end

      it 'generates correct URL for production with subdomain' do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
        business.update!(host_type: 'subdomain')
        
        url = controller_instance.send(:generate_referral_url, business, 'TEST123')
        expect(url).to eq("https://#{business.hostname}.bizblasts.com?ref=TEST123")
      end

      it 'generates correct URL for production with custom domain' do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
        # Create a business with all requirements for custom_domain_allow?
        custom_business = create(:business, 
                                hostname: 'example.com', 
                                host_type: 'custom_domain',
                                tier: 'premium',
                                status: 'cname_active',
                                render_domain_added: true,
                                domain_health_verified: true)
        
        url = controller_instance.send(:generate_referral_url, custom_business, 'TEST123')
        expect(url).to eq("https://example.com?ref=TEST123")
      end
    end
  end

  describe 'security and authorization' do
    context 'cross-tenant access prevention' do
      let(:other_business) { create(:business, hostname: 'otherbiz') }
      
      before do
        sign_in user
        # Enable referral program for other business
        other_business.update!(referral_program_enabled: true)
        other_business.create_referral_program!(
          active: true,
          referrer_reward_type: 'points',
          referrer_reward_value: 100,
          referral_code_discount_amount: 10.0,
          min_purchase_amount: 0.0
        )
      end

      it 'prevents access to other business referral data' do
        # Create a referral for the original business first
        create(:referral, business: business, referrer: user)
        
        # Switch to other business tenant
        ActsAsTenant.current_tenant = other_business
        request.host = "#{other_business.hostname}.lvh.me"
        
        get :show

        # Should not show referrals from the original business
        expect(assigns(:my_referrals)).to be_empty
      end
    end

    context 'authentication and authorization' do
      it 'requires authentication' do
        get :show
        expect(response).to redirect_to(new_user_session_path)
      end

      it 'allows client users to access functionality' do
        sign_in user
        get :show
        
        expect(response).to have_http_status(:success)
        expect(assigns(:referral_code)).to be_present
      end

      it 'restricts non-client users from full functionality' do
        manager_user = create(:user, role: :manager, business: business)
        sign_in manager_user
        
        get :show
        
        expect(response).to have_http_status(:success)
        expect(assigns(:referral_code)).to be_nil
        expect(flash.now[:alert]).to include('only available for client users')
      end
    end
  end
end 