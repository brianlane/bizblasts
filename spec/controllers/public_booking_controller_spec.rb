require 'rails_helper'

RSpec.describe Public::BookingController, type: :controller do
  let!(:business) { create(:business, :with_default_tax_rate, host_type: 'subdomain') }
  let!(:service) { create(:service, business: business, name: 'Test Service', price: 100.00, duration: 30) }
  let!(:staff_member) { create(:staff_member, business: business, name: 'Test Staff') }
  let!(:user) { create(:user, :client) }
  let!(:tenant_customer) { create(:tenant_customer, business: business, email: user.email, first_name: user.first_name, last_name: user.last_name) }

  before do
    business.save! unless business.persisted?
    ActsAsTenant.current_tenant = business
    set_tenant(business)
    @request.host = 'testbiz.lvh.me'
    sign_in user
    create(:services_staff_member, service: service, staff_member: staff_member)
  end

  describe 'POST #create' do
    before do
      # Mock the checkout session creation for the redirect
      allow(StripeService).to receive(:create_payment_checkout_session_for_booking).and_return({
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

    it 'creates booking and redirects to confirmation for standard services' do
      post :create, params: valid_booking_params
      
      # Should redirect to confirmation page for standard services
      booking = Booking.last
      expect(response).to redirect_to(tenant_booking_confirmation_path(booking))
      
      # Verify booking was created
      expect(Booking.count).to eq(1)
      expect(booking).to be_present
      expect(booking.service).to eq(service)
      expect(booking.staff_member).to eq(staff_member)
      expect(booking.status).to eq('confirmed')
      expect(booking.invoice).to be_present
      
      # Verify invoice has proper tax calculations
      invoice = booking.invoice
      expect(invoice.tax_rate).to be_present
      expect(invoice.tax_rate).to eq(business.default_tax_rate)
      expect(invoice.original_amount).to be_within(0.01).of(100.00)
      expect(invoice.tax_amount).to be_within(0.01).of(9.80) # 9.8% of $100
      expect(invoice.total_amount).to be_within(0.01).of(109.80) # $100 + $9.80 tax
      
      # Verify Stripe service was NOT called for standard services
      expect(StripeService).not_to have_received(:create_payment_checkout_session_for_booking)
    end

    context 'with experience service' do
      let!(:experience_service) { create(:service, business: business, name: 'Experience Service', price: 50.00, duration: 30, service_type: :experience, min_bookings: 1, max_bookings: 5, spots: 5) }
      let(:experience_booking_params) do
        {
          booking: {
            service_id: experience_service.id,
            staff_member_id: staff_member.id,
            start_time: 1.day.from_now,
            notes: 'Test experience booking'
          }
        }
      end

      before do
        create(:services_staff_member, service: experience_service, staff_member: staff_member)
      end

      it 'redirects to Stripe Checkout for experience services' do
        post :create, params: experience_booking_params
        
        # Should redirect to Stripe for experience services
        expect(response).to redirect_to('https://checkout.stripe.com/pay/cs_booking_test_123')
        
        # Verify booking was NOT created yet (will be created after payment)
        expect(Booking.count).to eq(0)
        
        # Verify Stripe service was called
        expect(StripeService).to have_received(:create_payment_checkout_session_for_booking)
      end

      context 'when Stripe error occurs' do
        before do
          allow(StripeService).to receive(:create_payment_checkout_session_for_booking)
            .and_raise(Stripe::StripeError.new('Stripe connection error'))
        end

        it 'redirects to booking form with error message' do
          post :create, params: experience_booking_params
          
          expect(response).to redirect_to(new_tenant_booking_path(service_id: experience_service.id, staff_member_id: staff_member.id))
          expect(flash[:alert]).to include('Could not connect to Stripe')
          
          # Verify no booking was created
          expect(Booking.count).to eq(0)
        end
      end

      context 'when booking amount is too small' do
        before do
          allow(StripeService).to receive(:create_payment_checkout_session_for_booking)
            .and_raise(ArgumentError, "Payment amount must be at least $0.50 USD")
        end

        it 'redirects to booking form with error message' do
          post :create, params: experience_booking_params
          
          expect(response).to redirect_to(new_tenant_booking_path(service_id: experience_service.id, staff_member_id: staff_member.id))
          expect(flash[:alert]).to include('This booking amount is too small for online payment')
          
          # Verify no booking was created
          expect(Booking.count).to eq(0)
        end
      end
    end

    context 'when staff user creates booking for client' do
      let(:staff_user) { create(:user, :staff, business: business) }
      let(:valid_staff_booking_params) do
        {
          booking: {
            service_id: service.id,
            staff_member_id: staff_member.id,
            start_time: 1.day.from_now,
            notes: 'Test booking',
            tenant_customer_attributes: {
              first_name: 'John',
              last_name: 'Doe',
              email: 'john.doe@example.com',
              phone: '555-1234'
            }
          }
        }
      end

      before do
        sign_out user
        sign_in staff_user
      end

      it 'creates booking and redirects to confirmation (not Stripe)' do
        post :create, params: valid_staff_booking_params
        
        # Should redirect to confirmation page, not Stripe
        booking = Booking.last
        expect(response).to redirect_to(tenant_booking_confirmation_path(booking))
        expect(flash[:notice]).to eq('Booking was successfully created.')
        
        # Verify booking was created
        expect(booking).to be_present
        expect(booking.service).to eq(service)
        expect(booking.staff_member).to eq(staff_member)
        expect(booking.invoice).to be_present
        
        # Verify invoice has proper tax calculations
        invoice = booking.invoice
        expect(invoice.tax_rate).to be_present
        expect(invoice.tax_rate).to eq(business.default_tax_rate)
        expect(invoice.tax_amount).to be_within(0.01).of(9.80) # 9.8% of $100
        expect(invoice.total_amount).to be_within(0.01).of(109.80) # $100 + $9.80 tax
        
        # Verify Stripe service was NOT called
        expect(StripeService).not_to have_received(:create_payment_checkout_session_for_booking)
      end
    end

    context 'when manager user creates booking for client' do
      let(:manager_user) { create(:user, :manager, business: business) }
      let(:valid_manager_booking_params) do
        {
          booking: {
            service_id: service.id,
            staff_member_id: staff_member.id,
            start_time: 1.day.from_now,
            notes: 'Test booking',
            tenant_customer_attributes: {
              first_name: 'Jane',
              last_name: 'Smith',
              email: 'jane.smith@example.com',
              phone: '555-5678'
            }
          }
        }
      end

      before do
        sign_out user
        sign_in manager_user
      end

      it 'creates booking and redirects to confirmation (not Stripe)' do
        post :create, params: valid_manager_booking_params
        
        # Should redirect to confirmation page, not Stripe
        booking = Booking.last
        expect(response).to redirect_to(tenant_booking_confirmation_path(booking))
        expect(flash[:notice]).to eq('Booking was successfully created.')
        
        # Verify booking was created
        expect(booking).to be_present
        expect(booking.service).to eq(service)
        expect(booking.staff_member).to eq(staff_member)
        expect(booking.invoice).to be_present
        
        # Verify invoice has proper tax calculations
        invoice = booking.invoice
        expect(invoice.tax_rate).to be_present
        expect(invoice.tax_rate).to eq(business.default_tax_rate)
        expect(invoice.tax_amount).to be_within(0.01).of(9.80) # 9.8% of $100
        expect(invoice.total_amount).to be_within(0.01).of(109.80) # $100 + $9.80 tax
        
        # Verify Stripe service was NOT called
        expect(StripeService).not_to have_received(:create_payment_checkout_session_for_booking)
      end
    end

    context 'when staff user does not select a customer' do
      let(:staff_user) { create(:user, :staff, business: business) }
      let(:invalid_booking_params) do
        {
          booking: {
            service_id: service.id,
            staff_member_id: staff_member.id,
            tenant_customer_id: "",  # Empty customer ID
            start_time: 1.day.from_now,
            notes: 'Test booking',
            tenant_customer_attributes: {}  # Empty customer attributes
          }
        }
      end

      before do
        sign_out user
        sign_in staff_user
      end

      it 'redirects with flash error instead of 422' do
        post :create, params: invalid_booking_params
        
        expect(response).to redirect_to(new_tenant_booking_path(service_id: service.id, staff_member_id: staff_member.id))
        expect(flash[:alert]).to eq('Please select a customer or provide customer details to create a booking.')
        
        # Verify no booking was created
        expect(Booking.count).to eq(0)
      end
    end

    context 'when guest user does not provide contact information' do
      let(:invalid_guest_booking_params) do
        {
          booking: {
            service_id: service.id,
            staff_member_id: staff_member.id,
            start_time: 1.day.from_now,
            notes: 'Test booking',
            tenant_customer_attributes: {}  # Empty customer attributes
          }
        }
      end

      before do
        sign_out user  # Ensure no user is signed in (guest scenario)
      end

      it 'redirects with flash error instead of 422' do
        post :create, params: invalid_guest_booking_params
        
        expect(response).to redirect_to(new_tenant_booking_path(service_id: service.id, staff_member_id: staff_member.id))
        expect(flash[:alert]).to eq('Please provide your contact information to create a booking.')
        
        # Verify no booking was created
        expect(Booking.count).to eq(0)
      end
    end
  end
end 