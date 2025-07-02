require 'rails_helper'

RSpec.describe Public::LoyaltyController, type: :controller do
  let(:business) { create(:business) }
  let(:loyalty_program) { create(:loyalty_program, business: business, active: true) }
  let(:user) { create(:user, role: :client) }
  let(:tenant_customer) { create(:tenant_customer, business: business, email: user.email) }

  before do
    ActsAsTenant.current_tenant = business
    business.update!(loyalty_program_enabled: true, referral_program_enabled: true)
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
    context 'when user is authenticated' do
      before { sign_in user }

      context 'when customer has loyalty account' do
        let!(:earned_transaction) { create(:loyalty_transaction, 
                                          tenant_customer: tenant_customer, 
                                          transaction_type: 'earned', 
                                          points_amount: 150) }
        let!(:redeemed_transaction) { create(:loyalty_transaction, 
                                            tenant_customer: tenant_customer, 
                                            transaction_type: 'redeemed', 
                                            points_amount: -50) }

        it 'renders the loyalty dashboard' do
          get :show
          
          expect(response).to have_http_status(:success)
          expect(assigns(:business)).to eq(business)
          expect(assigns(:customer)).to eq(tenant_customer)
          expect(assigns(:loyalty_summary)).to be_present
          expect(assigns(:loyalty_history)).to include(earned_transaction, redeemed_transaction)
        end

        it 'calculates loyalty summary correctly' do
          get :show
          
          summary = assigns(:loyalty_summary)
          expect(summary[:current_points]).to eq(100) # 150 - 50
          expect(summary[:total_earned]).to eq(150)
          expect(summary[:total_redeemed]).to eq(50)
        end

        it 'provides redemption options' do
          get :show
          
          expect(assigns(:redemption_options)).to be_an(Array)
          # Should only show options customer can afford
          assigns(:redemption_options).each do |option|
            expect(option[:points]).to be <= 100
          end
        end

        it 'shows active redemptions' do
          discount_code = create(:discount_code, 
                               business: business, 
                               tenant_customer: tenant_customer,
                               active: true,
                               points_redeemed: 50)
          
          get :show
          
          expect(assigns(:active_redemptions)).to include(discount_code)
        end
      end

      context 'when customer has no loyalty account' do
        it 'renders with no customer data' do
          get :show
          
          expect(response).to have_http_status(:success)
          expect(assigns(:customer)).to be_nil
          expect(assigns(:loyalty_summary)).to be_nil
        end
      end
    end

    context 'when user is not authenticated' do
      it 'redirects to sign in' do
        get :show
        
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context 'when business not found' do
      before do
        # Use a nonexistent hostname to ensure no business is found
        request.host = "nonexistent.lvh.me"
        ActsAsTenant.current_tenant = nil
        sign_in user
      end

      it 'returns 404' do
        get :show
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when loyalty program is disabled' do
      before do
        business.update!(loyalty_program_enabled: false)
        sign_in user
      end

      it 'redirects with error message' do
        get :show
        
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include('not available')
      end
    end
  end

  describe 'POST #redeem_points' do
    let!(:earned_transaction) { create(:loyalty_transaction, 
                                      tenant_customer: tenant_customer, 
                                      transaction_type: 'earned', 
                                      points_amount: 200) }

    before do
      sign_in user
      # Mock Stripe coupon creation
      allow(Stripe::Coupon).to receive(:create).and_return(
        double('coupon', id: 'test_coupon_123', amount_off: 1000, currency: 'usd')
      )
    end

    context 'with valid points amount' do
      it 'redeems points successfully' do
        expect {
          post :redeem_points, params: { points: 100 }
        }.to change { LoyaltyTransaction.redeemed.count }.by(1)
          .and change { DiscountCode.count }.by(1)

        expect(response).to redirect_to(tenant_loyalty_path)
        expect(flash[:notice]).to include('Successfully redeemed')
        
        # Check discount code was created
        discount_code = DiscountCode.last
        expect(discount_code.tenant_customer).to eq(tenant_customer)
        expect(discount_code.points_redeemed).to eq(100)
      end

      it 'handles Stripe errors gracefully' do
        allow(Stripe::Coupon).to receive(:create).and_raise(Stripe::StripeError.new('Test error'))
        
        expect {
          post :redeem_points, params: { points: 100 }
        }.not_to change { LoyaltyTransaction.count }

        expect(response).to redirect_to(tenant_loyalty_path)
        expect(flash[:alert]).to include('error')
      end
    end

    context 'with insufficient points' do
      it 'returns error without redeeming' do
        expect {
          post :redeem_points, params: { points: 300 }
        }.not_to change { LoyaltyTransaction.count }

        expect(response).to redirect_to(tenant_loyalty_path)
        expect(flash[:alert]).to include('Insufficient points')
      end
    end

    context 'with invalid points amount' do
      it 'returns error for zero points' do
        post :redeem_points, params: { points: 0 }

        expect(response).to redirect_to(tenant_loyalty_path)
        expect(flash[:alert]).to include('Invalid points amount')
      end

      it 'returns error for negative points' do
        post :redeem_points, params: { points: -50 }

        expect(response).to redirect_to(tenant_loyalty_path)
        expect(flash[:alert]).to include('Invalid points amount')
      end
    end

    context 'when user is not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        post :redeem_points, params: { points: 100 }

        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context 'when customer has no loyalty account' do
      let(:user_without_customer) { create(:user, role: :client, email: 'other@example.com') }
      
      before { sign_in user_without_customer }

      it 'returns error' do
        post :redeem_points, params: { points: 100 }

        expect(response).to redirect_to(tenant_loyalty_path)
        expect(flash[:alert]).to include('No loyalty account found')
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

    describe '#set_customer' do
      before do
        controller_instance.instance_variable_set(:@business, business)
        allow(controller_instance).to receive(:current_user).and_return(user)
        tenant_customer # Ensure tenant_customer is created
      end

      it 'finds customer by user email' do
        controller_instance.send(:set_customer)
        expect(controller_instance.instance_variable_get(:@customer)).to eq(tenant_customer)
      end

      it 'returns nil when user not authenticated' do
        allow(controller_instance).to receive(:current_user).and_return(nil)
        controller_instance.send(:set_customer)
        expect(controller_instance.instance_variable_get(:@customer)).to be_nil
      end

      it 'returns nil when customer not found' do
        allow(controller_instance).to receive(:current_user).and_return(
          create(:user, email: 'notfound@example.com')
        )
        controller_instance.send(:set_customer)
        expect(controller_instance.instance_variable_get(:@customer)).to be_nil
      end
    end
  end

  describe 'security and authorization' do
    context 'cross-tenant access prevention' do
      let(:other_business) { create(:business, hostname: 'otherbiz') }
      let(:other_customer) { create(:tenant_customer, business: other_business) }
      
      before { sign_in user }

      it 'prevents access to other business loyalty data' do
        # Switch to other business tenant
        ActsAsTenant.current_tenant = other_business
        
        get :show

        # Should not find customer from different business
        expect(assigns(:customer)).to be_nil
      end
    end

    context 'parameter validation' do
      before { sign_in user }

      it 'validates required authentication' do
        sign_out user
        
        get :show
        expect(response).to redirect_to(new_user_session_path)
      end

      it 'sanitizes points parameter' do
        tenant_customer # Ensure customer exists
        
        post :redeem_points, params: { points: 'invalid' }

        expect(response).to redirect_to(tenant_loyalty_path)
        expect(flash[:alert]).to include('Invalid points amount')
      end
    end
  end
end 