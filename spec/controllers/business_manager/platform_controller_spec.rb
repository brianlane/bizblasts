require 'rails_helper'

RSpec.describe BusinessManager::PlatformController, type: :controller do
  let(:business) { create(:business, subdomain: 'testbusiness', hostname: 'testbusiness') }
  let(:manager_user) { create(:user, :manager, business: business) }
  
  before do
    ActsAsTenant.current_tenant = business
    set_tenant(business)
    @request.host = 'testbusiness.lvh.me'
    sign_in manager_user
    allow(controller).to receive(:current_business).and_return(business)
    
    # Mock Stripe API key configuration
    allow(PlatformLoyaltyService).to receive(:configure_stripe_api_key)
  end

  describe 'GET #index' do
    let!(:platform_transactions) do
      [
        create(:platform_loyalty_transaction, business: business, transaction_type: 'earned'),
        create(:platform_loyalty_transaction, business: business, transaction_type: 'redeemed')
      ]
    end
    
    let!(:platform_referrals) do
      [
        create(:platform_referral, referrer_business: business, status: 'qualified')
      ]
    end
    
    let!(:discount_codes) do
      [
        create(:platform_discount_code, business: business, status: 'active')
      ]
    end
    
    before do
      business.add_platform_loyalty_points!(150, 'Test setup points', nil)
    end
    
    it 'loads platform loyalty dashboard data' do
      get :index
      
      expect(response).to be_successful
      expect(assigns(:loyalty_summary)).to be_present
      expect(assigns(:recent_transactions)).to include(*platform_transactions)
      expect(assigns(:recent_referrals)).to include(*platform_referrals)
      expect(assigns(:discount_codes)).to include(*discount_codes)
      expect(assigns(:redemption_options)).to be_an(Array)
    end
    
    it 'limits recent transactions to 10' do
      create_list(:platform_loyalty_transaction, 15, business: business)
      
      get :index
      
      expect(assigns(:recent_transactions).count).to eq(10)
    end
    
    it 'calculates available redemption options based on points' do
      business.add_platform_loyalty_points!(100, 'Additional test points', nil) # Total will be 250
      
      get :index
      
      redemption_options = assigns(:redemption_options)
      expect(redemption_options.map { |opt| opt[:points] }).to include(100, 200)
      expect(redemption_options.map { |opt| opt[:points] }).not_to include(300) # Not enough points
    end
  end

  describe 'POST #generate_referral_code' do
    context 'when business has no referral code' do
      it 'generates new referral code' do
        expect(business.platform_referral_code).to be_nil
        
        post :generate_referral_code, format: :json
        
        expect(response).to be_successful
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be true
        expect(json_response['referral_code']).to be_present
        expect(json_response['referral_code']).to match(/^BIZ-.+-[A-Z0-9]{6}$/)
        
        expect(business.reload.platform_referral_code).to eq(json_response['referral_code'])
      end
      
      it 'returns success message' do
        post :generate_referral_code, format: :json
        
        json_response = JSON.parse(response.body)
        expect(json_response['message']).to eq('Referral code generated successfully!')
      end
    end
    
    context 'when business already has referral code' do
      before do
        business.update!(platform_referral_code: 'BIZ-TB-EXISTING')
      end
      
      it 'returns existing referral code' do
        post :generate_referral_code, format: :json
        
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be true
        expect(json_response['referral_code']).to eq('BIZ-TB-EXISTING')
      end
    end
    
    context 'when code generation fails' do
      before do
        allow(PlatformLoyaltyService).to receive(:generate_business_platform_referral_code)
          .and_raise(StandardError.new('Database error'))
      end
      
      it 'returns error response' do
        post :generate_referral_code, format: :json
        
        expect(response).to have_http_status(422)
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be false
        expect(json_response['error']).to eq('Failed to generate referral code')
      end
    end
    
    context 'with HTML request' do
      it 'redirects with flash message on success' do
        post :generate_referral_code
        
        expect(response).to redirect_to(business_manager_platform_index_path)
        expect(flash[:success]).to eq('Referral code generated successfully!')
      end
    end
  end

  describe 'POST #redeem_points' do
    before do
      business.add_platform_loyalty_points!(500, 'Test redeem setup points', nil)
    end
    
    context 'with valid point redemption' do
      let(:mock_stripe_coupon) { double('Stripe::Coupon', id: 'coupon_test_loyalty_123') }
      
      before do
        allow(Stripe::Coupon).to receive(:create).and_return(mock_stripe_coupon)
      end
      
      it 'redeems points and creates discount code' do
        post :redeem_points, params: { points_amount: 200 }, format: :json
        
        expect(response).to be_successful
        json_response = JSON.parse(response.body)
        
        expect(json_response['success']).to be true
        expect(json_response['points_redeemed']).to eq(200)
        expect(json_response['discount_amount']).to eq(20.0)
        expect(json_response['discount_code']).to be_present
        expect(json_response['message']).to include('Successfully redeemed 200 points')
        
        expect(business.reload.platform_loyalty_points).to eq(300) # 500 - 200
      end
      
      it 'creates Stripe coupon with correct parameters' do
        post :redeem_points, params: { points_amount: 100 }, format: :json
        
        expect(Stripe::Coupon).to have_received(:create).with(
          hash_including(
            amount_off: 1000, # $10 in cents
            currency: 'usd',
            duration: 'once',
                          name: 'BizBlasts Loyalty Reward - $10 Off'
          )
        )
      end
    end
    
    context 'with insufficient points' do
      it 'returns error for insufficient points' do
        post :redeem_points, params: { points_amount: 600 }, format: :json # More than 500 available
        
        expect(response).to have_http_status(422)
        json_response = JSON.parse(response.body)
        
        expect(json_response['success']).to be false
        expect(json_response['error']).to eq('Insufficient loyalty points')
      end
    end
    
    context 'with invalid point amounts' do
      it 'rejects non-100 multiples' do
        post :redeem_points, params: { points_amount: 150 }, format: :json
        
        expect(response).to have_http_status(422)
        json_response = JSON.parse(response.body)
        
        expect(json_response['success']).to be false
        expect(json_response['error']).to eq('Points must be in multiples of 100')
      end
      
      it 'rejects amounts over maximum' do
        post :redeem_points, params: { points_amount: 1100 }, format: :json
        
        expect(response).to have_http_status(422)
        json_response = JSON.parse(response.body)
        
        expect(json_response['success']).to be false
        expect(json_response['error']).to eq('Maximum 1000 points can be redeemed at once')
      end
    end
    
    context 'when Stripe error occurs' do
      before do
        allow(Stripe::Coupon).to receive(:create).and_raise(Stripe::APIError.new('Stripe error'))
      end
      
      it 'returns error response' do
        post :redeem_points, params: { points_amount: 100 }, format: :json
        
        expect(response).to have_http_status(422)
        json_response = JSON.parse(response.body)
        
        expect(json_response['success']).to be false
        expect(json_response['error']).to eq('Failed to redeem loyalty points')
      end
    end
    
    context 'with HTML request' do
      let(:mock_stripe_coupon) { double('Stripe::Coupon', id: 'coupon_test_loyalty_123') }
      
      before do
        allow(Stripe::Coupon).to receive(:create).and_return(mock_stripe_coupon)
      end
      
      it 'redirects with flash message on success' do
        post :redeem_points, params: { points_amount: 100 }
        
        expect(response).to redirect_to(business_manager_platform_index_path)
        expect(flash[:success]).to include('Successfully redeemed 100 points')
      end
      
      it 'redirects with error message on failure' do
        post :redeem_points, params: { points_amount: 1100 } # Invalid amount
        
        expect(response).to redirect_to(business_manager_platform_index_path)
        expect(flash[:error]).to eq('Maximum 1000 points can be redeemed at once')
      end
    end
  end

  describe 'GET #transactions' do
    let!(:transactions) do
      create_list(:platform_loyalty_transaction, 30, business: business)
    end
    
    it 'returns paginated transactions' do
      get :transactions, format: :json
      
      expect(response).to be_successful
      json_response = JSON.parse(response.body)
      
      expect(json_response['transactions']).to be_an(Array)
      expect(json_response['transactions'].count).to eq(25) # Default page size
      expect(json_response['meta']['total_count']).to eq(30)
      expect(json_response['meta']['total_pages']).to eq(2)
    end
    
    it 'includes transaction details in JSON response' do
      get :transactions, format: :json
      
      json_response = JSON.parse(response.body)
      transaction_data = json_response['transactions'].first
      
      expect(transaction_data).to include(
        'id' => be_present,
        'transaction_type' => be_present,
        'points_amount' => be_present,
        'description' => be_present,
        'created_at' => be_present
      )
    end
  end

  describe 'GET #referrals' do
    let!(:referrals) do
      create_list(:platform_referral, 5, referrer_business: business, status: 'qualified')
    end
    
    it 'returns paginated referrals' do
      get :referrals, format: :json
      
      expect(response).to be_successful
      json_response = JSON.parse(response.body)
      
      expect(json_response['referrals']).to be_an(Array)
      expect(json_response['referrals'].count).to eq(5)
      expect(json_response['meta']['total_count']).to eq(5)
    end
    
    it 'includes referral details in JSON response' do
      get :referrals, format: :json
      
      json_response = JSON.parse(response.body)
      referral_data = json_response['referrals'].first
      
      expect(referral_data).to include(
        'id' => be_present,
        'referral_code' => be_present,
        'status' => 'qualified',
        'referred_business' => hash_including(
          'name' => be_present,
          'tier' => be_present
        )
      )
    end
  end

  describe 'GET #discount_codes' do
    let!(:discount_codes) do
      create_list(:platform_discount_code, 3, business: business)
    end
    
    it 'returns paginated discount codes' do
      get :discount_codes, format: :json
      
      expect(response).to be_successful
      json_response = JSON.parse(response.body)
      
      expect(json_response['discount_codes']).to be_an(Array)
      expect(json_response['discount_codes'].count).to eq(3)
    end
    
    it 'includes discount code details in JSON response' do
      get :discount_codes, format: :json
      
      json_response = JSON.parse(response.body)
      code_data = json_response['discount_codes'].first
      
      expect(code_data).to include(
        'id' => be_present,
        'code' => be_present,
        'points_redeemed' => be_present,
        'discount_amount' => be_present,
        'status' => 'active'
      )
    end
  end

  describe 'authorization' do
    context 'when user is not a business manager' do
      let(:regular_user) { create(:user) }
      
      before do
        sign_out manager_user
        sign_in regular_user
      end
      
      it 'denies access to index action' do
        get :index
        
        expect(response).to redirect_to(dashboard_path)
        expect(flash[:alert]).to eq('You are not authorized to access this area.')
      end
      
      it 'returns JSON error for AJAX requests' do
        get :index, format: :json
        
        expect(response).to have_http_status(302)
        expect(response).to redirect_to(dashboard_path)
      end
    end
    
    context 'when user is not signed in' do
      before do
        sign_out manager_user
      end
      
      it 'redirects to sign in page' do
        get :index
        
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end 