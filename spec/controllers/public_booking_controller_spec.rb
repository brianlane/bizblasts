require 'rails_helper'

RSpec.describe Public::BookingController, type: :controller do
  let!(:business) { create(:business, subdomain: 'testtenant', hostname: 'testtenant', stripe_account_id: 'acct_test123') }
  let!(:service) { create(:service, business: business, name: 'Test Service', price: 50.00, duration: 30) }
  let!(:staff_member) { create(:staff_member, business: business, name: 'Test Staff') }
  let!(:user) { create(:user, email: 'test@example.com') }
  let!(:tenant_customer) { create(:tenant_customer, business: business, email: user.email) }

  before do
    business.save! unless business.persisted?
    ActsAsTenant.current_tenant = business
    set_tenant(business)
    @request.host = 'testtenant.lvh.me'
    sign_in user
    create(:services_staff_member, service: service, staff_member: staff_member)
  end

  describe 'POST #create' do
    before do
      # Mock the checkout session creation for the redirect
      allow(StripeService).to receive(:create_payment_checkout_session).and_return({
        session: double('Stripe::Checkout::Session', url: 'https://checkout.stripe.com/pay/cs_booking_test_123')
      })
    end

    let(:valid_booking_params) do
      {
        booking: {
          service_id: service.id,
          staff_member_id: staff_member.id,
          start_time: 1.day.from_now,
          notes: 'Test booking'
        }
      }
    end

    it 'creates booking and redirects to Stripe Checkout' do
      post :create, params: valid_booking_params
      
      # Should redirect to Stripe instead of the confirmation page
      expect(response).to redirect_to('https://checkout.stripe.com/pay/cs_booking_test_123')
      
      # Verify booking was created
      booking = Booking.last
      expect(booking).to be_present
      expect(booking.tenant_customer).to eq(tenant_customer)
      expect(booking.service).to eq(service)
      expect(booking.staff_member).to eq(staff_member)
      expect(booking.invoice).to be_present
      
      # Verify Stripe service was called with correct parameters
      expect(StripeService).to have_received(:create_payment_checkout_session).with(
        invoice: booking.invoice,
        success_url: tenant_booking_confirmation_path(booking, payment_success: true),
        cancel_url: tenant_booking_confirmation_path(booking, payment_cancelled: true)
      )
    end

    context 'when Stripe error occurs' do
      before do
        allow(StripeService).to receive(:create_payment_checkout_session)
          .and_raise(Stripe::StripeError.new('Stripe connection error'))
      end

      it 'redirects to confirmation with error message' do
        post :create, params: valid_booking_params
        
        booking = Booking.last
        expect(response).to redirect_to(tenant_booking_confirmation_path(booking))
        expect(flash[:alert]).to include('Could not connect to Stripe')
      end
    end

    context 'when booking amount is too small' do
      before do
        allow(StripeService).to receive(:create_payment_checkout_session)
          .and_raise(ArgumentError, "Payment amount must be at least $0.50 USD")
      end

      it 'redirects to confirmation with error message' do
        post :create, params: valid_booking_params
        
        booking = Booking.last
        expect(response).to redirect_to(tenant_booking_confirmation_path(booking))
        expect(flash[:alert]).to include('This booking amount is too small for online payment')
      end
    end
  end
end 