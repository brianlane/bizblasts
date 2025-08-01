require 'rails_helper'

RSpec.describe Public::TipsController, type: :controller do
  let(:business) { create(:business, subdomain: 'testtip', hostname: 'testtip', stripe_account_id: 'acct_test123') }
  let(:user) { create(:user, :client, email: 'customer@example.com') }
  let(:tenant_customer) { create(:tenant_customer, business: business, email: user.email, first_name: user.first_name, last_name: user.last_name) }
  let(:experience_service) { create(:service, business: business, service_type: :experience, duration: 60, min_bookings: 1, max_bookings: 10, spots: 5, tips_enabled: true) }
  let(:booking) { create(:booking, business: business, service: experience_service, tenant_customer: tenant_customer, start_time: 2.hours.ago, status: :completed) }
  let(:token) { booking.generate_tip_token }

  before do
    request.host = host_for(business)
    ActsAsTenant.current_tenant = business
    sign_in user
    
    # Mock Stripe checkout session creation
    allow(StripeService).to receive(:create_tip_payment_session).and_return({
      session: double('Stripe::Checkout::Session', url: 'https://checkout.stripe.com/pay/cs_tip_test_123')
    })
  end

  describe 'GET #new' do
    context 'when tips are enabled and booking is eligible' do
      it 'renders the new tip form' do
        get :new, params: { booking_id: booking.id, token: token }
        
        expect(response).to have_http_status(:ok)
        expect(assigns(:booking)).to eq(booking)
        expect(assigns(:tip)).to be_a_new(Tip)
      end
    end

    context 'when service has tips disabled' do
      let(:no_tip_service) { create(:service, business: business, service_type: :experience, tips_enabled: false, min_bookings: 1, max_bookings: 10, spots: 5) }
      let(:no_tip_booking) { create(:booking, business: business, service: no_tip_service, tenant_customer: tenant_customer, start_time: 2.hours.ago, status: :completed) }
      let(:no_tip_token) { no_tip_booking.generate_tip_token }

      it 'redirects with error message' do
        get :new, params: { booking_id: no_tip_booking.id, token: no_tip_token }
        
        expect(response).to redirect_to(tenant_my_booking_path(no_tip_booking))
        expect(flash[:alert]).to eq('This service is not eligible for tips.')
      end
    end

    context 'when booking is not eligible for tips' do
      let(:standard_service) { create(:service, business: business, service_type: :standard) }
      let(:standard_booking) { create(:booking, business: business, service: standard_service, tenant_customer: tenant_customer, status: :completed) }
      let(:standard_token) { standard_booking.generate_tip_token }

      it 'redirects with error message' do
        get :new, params: { booking_id: standard_booking.id, token: standard_token }
        
        expect(response).to redirect_to(tenant_my_booking_path(standard_booking))
        expect(flash[:alert]).to eq('This service is not eligible for tips.')
      end
    end

    context 'when tip has already been processed' do
      before do
        create(:tip, :completed, business: business, booking: booking, tenant_customer: tenant_customer)
      end

      it 'redirects with error message' do
        get :new, params: { booking_id: booking.id, token: token }
        
        expect(response).to redirect_to("#{tip_path(booking.tip)}?token=#{token}")
        expect(flash[:notice]).to eq('A tip has already been provided for this booking.')
      end
    end

    context 'when user is not authenticated' do
      before { sign_out user }

      it 'allows access with valid token (token-based access)' do
        get :new, params: { booking_id: booking.id, token: token }
        
        expect(response).to have_http_status(:ok)
        expect(assigns(:booking)).to eq(booking)
        expect(assigns(:tip)).to be_a_new(Tip)
      end
    end
  end

  describe 'POST #create' do
    context 'with valid parameters' do
      it 'creates tip and redirects to Stripe checkout' do
        expect {
          post :create, params: { booking_id: booking.id, token: token, tip_amount: '10.00' }
        }.to change(Tip, :count).by(1)
        
        tip = Tip.last
        expect(tip.amount).to eq(10.00)
        expect(tip.business).to eq(business)
        expect(tip.booking).to eq(booking)
        expect(tip.tenant_customer).to eq(tenant_customer)
        expect(tip.status).to eq('pending')
        
        expect(response).to redirect_to('https://checkout.stripe.com/pay/cs_tip_test_123')
        
        # Verify Stripe service was called
        expect(StripeService).to have_received(:create_tip_payment_session)
      end
    end

    context 'with invalid parameters' do
      it 'does not create tip and redirects with error' do
        expect {
          post :create, params: { booking_id: booking.id, token: token, tip_amount: '-5.00' }
        }.not_to change(Tip, :count)
        
        expect(response).to redirect_to(new_tip_path(booking_id: booking.id, token: token))
        expect(flash[:alert]).to be_present
      end
    end

    context 'when Stripe error occurs' do
      before do
        allow(StripeService).to receive(:create_tip_payment_session)
          .and_raise(Stripe::StripeError.new('Stripe connection error'))
      end

      it 'destroys tip and redirects with error message' do
        expect {
          post :create, params: { booking_id: booking.id, token: token, tip_amount: '10.00' }
        }.not_to change(Tip, :count)
        
        expect(response).to redirect_to(new_tip_path(booking_id: booking.id, token: token))
        expect(flash[:alert]).to include('Could not connect to payment processor')
      end
    end

    context 'when tip amount is too small' do
      it 'redirects with error message for small amount' do
        expect {
          post :create, params: { booking_id: booking.id, token: token, tip_amount: '0.25' }
        }.not_to change(Tip, :count)
        
        expect(response).to redirect_to(new_tip_path(booking_id: booking.id, token: token))
        expect(flash[:alert]).to eq('Minimum tip amount is $0.50.')
      end
    end

    context 'when service has tips disabled' do
      let(:no_tip_service) { create(:service, business: business, service_type: :experience, tips_enabled: false, min_bookings: 1, max_bookings: 10, spots: 5) }
      let(:no_tip_booking) { create(:booking, business: business, service: no_tip_service, tenant_customer: tenant_customer, start_time: 2.hours.ago, status: :completed) }
      let(:no_tip_token) { no_tip_booking.generate_tip_token }

      it 'redirects without creating tip' do
        expect {
          post :create, params: { booking_id: no_tip_booking.id, token: no_tip_token, tip_amount: '10.00' }
        }.not_to change(Tip, :count)
        
        expect(response).to redirect_to(tenant_my_booking_path(no_tip_booking))
        expect(flash[:alert]).to eq('This service is not eligible for tips.')
      end
    end
  end

  describe 'GET #success' do
    let(:tip) { create(:tip, :completed, business: business, booking: booking, tenant_customer: tenant_customer) }

    it 'redirects to booking with success message' do
      get :success, params: { booking_id: booking.id, id: tip.id, token: token }
      
      expect(response).to redirect_to(tenant_my_booking_path(booking))
      expect(flash[:notice]).to eq('Thank you for your tip! Your appreciation means a lot to our team.')
    end
  end

  describe 'GET #cancel' do
    context 'with pending tip' do
      it 'destroys tip and redirects with message' do
        tip = create(:tip, business: business, booking: booking, tenant_customer: tenant_customer, status: :pending)
        
        expect {
          get :cancel, params: { booking_id: booking.id, id: tip.id, token: token }
        }.to change(Tip, :count).by(-1)
        
        expect(response).to redirect_to(tenant_my_booking_path(booking))
        expect(flash[:notice]).to eq('Tip payment was cancelled.')
      end
    end

    context 'with completed tip' do
      it 'does not destroy tip and redirects with message' do
        tip = create(:tip, :completed, business: business, booking: booking, tenant_customer: tenant_customer)
        
        expect {
          get :cancel, params: { booking_id: booking.id, id: tip.id, token: token }
        }.not_to change(Tip, :count)
        
        expect(response).to redirect_to(tenant_my_booking_path(booking))
        expect(flash[:alert]).to eq('Cannot cancel a completed tip.')
      end
    end
  end
end 