# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Public::RentalBookingsController, type: :controller do
  let(:business) { create(:business) }
  let(:rental) { create(:product, :rental, business: business, rental_quantity_available: 5) }
  let(:customer) { create(:tenant_customer, business: business, email: 'customer@example.com') }
  let(:rental_booking) do
    create(:rental_booking,
           product: rental,
           tenant_customer: customer,
           business: business,
           status: 'pending_deposit',
           guest_access_token: 'valid_token_123')
  end

  before do
    request.host = "#{business.hostname}.lvh.me"
    ActsAsTenant.current_tenant = business
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe 'authorization for deposit endpoints' do
    context 'when accessing without authorization' do
      it 'redirects from pay_deposit without token or authentication' do
        get :pay_deposit, params: { id: rental_booking.id }
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq('You are not authorized to view this booking.')
      end

      it 'redirects from deposit_success without token or authentication' do
        get :deposit_success, params: { id: rental_booking.id }
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq('You are not authorized to view this booking.')
      end

      it 'redirects from deposit_cancel without token or authentication' do
        get :deposit_cancel, params: { id: rental_booking.id }
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq('You are not authorized to view this booking.')
      end

      it 'redirects from show without token or authentication' do
        get :show, params: { id: rental_booking.id }
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq('You are not authorized to view this booking.')
      end

      it 'redirects from confirmation without token or authentication' do
        get :confirmation, params: { id: rental_booking.id }
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq('You are not authorized to view this booking.')
      end
    end

    context 'when accessing with valid guest token' do
      it 'allows access to pay_deposit with valid token' do
        get :pay_deposit, params: { id: rental_booking.id, token: 'valid_token_123' }
        expect(response).to have_http_status(:success)
      end

      it 'allows access to deposit_success with valid token' do
        get :deposit_success, params: { id: rental_booking.id, token: 'valid_token_123' }
        expect(response).to have_http_status(:success)
      end

      it 'allows access to deposit_cancel with valid token' do
        get :deposit_cancel, params: { id: rental_booking.id, token: 'valid_token_123' }
        expect(response).to redirect_to(rental_booking_path(rental_booking, token: 'valid_token_123'))
      end

      it 'allows access to show with valid token' do
        get :show, params: { id: rental_booking.id, token: 'valid_token_123' }
        expect(response).to have_http_status(:success)
      end

      it 'allows access to confirmation with valid token' do
        get :confirmation, params: { id: rental_booking.id, token: 'valid_token_123' }
        expect(response).to be_successful
      end
    end

    context 'when signed in as the booking customer' do
      let(:user) { create(:user, :client, email: customer.email) }

      before do
        sign_in user
      end

      it 'allows access to pay_deposit when signed in as customer' do
        get :pay_deposit, params: { id: rental_booking.id }
        expect(response).to have_http_status(:success)
      end

      it 'allows access to deposit_success when signed in as customer' do
        get :deposit_success, params: { id: rental_booking.id }
        expect(response).to have_http_status(:success)
      end

      it 'allows access to deposit_cancel when signed in as customer' do
        get :deposit_cancel, params: { id: rental_booking.id }
        expect(response).to redirect_to(rental_booking_path(rental_booking))
      end

      it 'allows access to show when signed in as customer' do
        get :show, params: { id: rental_booking.id }
        expect(response).to have_http_status(:success)
      end

      it 'allows access to confirmation when signed in as customer' do
        get :confirmation, params: { id: rental_booking.id }
        expect(response).to be_successful
      end
    end

    context 'when signed in as different customer' do
      let(:other_customer) { create(:tenant_customer, business: business, email: 'other@example.com') }
      let(:other_user) { create(:user, :client, email: other_customer.email) }

      before do
        sign_in other_user
      end

      it 'denies access to pay_deposit when signed in as different customer' do
        get :pay_deposit, params: { id: rental_booking.id }
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq('You are not authorized to view this booking.')
      end

      it 'denies access to deposit_success when signed in as different customer' do
        get :deposit_success, params: { id: rental_booking.id }
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq('You are not authorized to view this booking.')
      end

      it 'denies access to deposit_cancel when signed in as different customer' do
        get :deposit_cancel, params: { id: rental_booking.id }
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq('You are not authorized to view this booking.')
      end
    end

    context 'when accessing with invalid token' do
      it 'raises RecordNotFound for pay_deposit with invalid token' do
        expect {
          get :pay_deposit, params: { id: rental_booking.id, token: 'invalid_token' }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it 'raises RecordNotFound for deposit_success with invalid token' do
        expect {
          get :deposit_success, params: { id: rental_booking.id, token: 'invalid_token' }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it 'raises RecordNotFound for deposit_cancel with invalid token' do
        expect {
          get :deposit_cancel, params: { id: rental_booking.id, token: 'invalid_token' }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe 'pay_deposit action functionality' do
    let(:user) { create(:user, :client, email: customer.email) }

    before do
      sign_in user
    end

    it 'redirects to booking page if deposit already paid' do
      rental_booking.update!(status: 'deposit_paid')

      get :pay_deposit, params: { id: rental_booking.id }
      expect(response).to redirect_to(rental_booking_path(rental_booking))
      expect(flash[:notice]).to eq('Deposit has already been paid.')
    end

    it 'renders the deposit form when pending' do
      get :pay_deposit, params: { id: rental_booking.id }
      expect(response).to have_http_status(:success)
    end
  end

  describe 'submit_deposit action' do
    let(:user) { create(:user, :client, email: customer.email) }
    let(:signature_service) { instance_double(ClientDocuments::SignatureService, capture!: true) }
    let(:workflow_service) { instance_double(ClientDocuments::WorkflowService, mark_signature_captured!: true) }
    let(:deposit_service) { instance_double(ClientDocuments::DepositService) }
    let(:checkout_session) { double(url: 'https://checkout.stripe.com/test_session', id: 'cs_123', payment_intent: 'pi_123') }

    before do
      sign_in user
      allow(ClientDocuments::SignatureService).to receive(:new).and_return(signature_service)
      allow(ClientDocuments::WorkflowService).to receive(:new).and_return(workflow_service)
      allow(ClientDocuments::DepositService).to receive(:new).and_return(deposit_service)
      allow(deposit_service).to receive(:initiate_checkout!).and_return({ session: checkout_session })
    end

    it 'redirects to Stripe checkout when signature provided' do
      post :submit_deposit, params: {
        id: rental_booking.id,
        signature_name: 'John Doe',
        signature_data: 'data:image/png;base64,AAAA'
      }

      expect(response).to redirect_to('https://checkout.stripe.com/test_session')
      expect(ClientDocuments::SignatureService).to have_received(:new)
      expect(ClientDocuments::DepositService).to have_received(:new)
    end

    it 're-renders form when signature is missing' do
      post :submit_deposit, params: { id: rental_booking.id, signature_name: '', signature_data: '' }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response).to render_template(:pay_deposit)
    end

    it 'redirects back when a Stripe error occurs' do
      allow(deposit_service).to receive(:initiate_checkout!).and_raise(Stripe::StripeError.new('stripe down'))

      post :submit_deposit, params: {
        id: rental_booking.id,
        signature_name: 'John Doe',
        signature_data: 'data:image/png;base64,AAAA'
      }

      expect(response).to redirect_to(rental_booking_path(rental_booking))
      expect(flash[:alert]).to eq('Unable to connect to payment provider. Please try again later.')
    end

    it 'prevents duplicate checkout sessions when status changes during processing (race condition)' do
      # Simulate a race condition where another request already processed the deposit
      # by changing the status after the initial load but before our lock
      allow_any_instance_of(RentalBooking).to receive(:lock!) do |booking|
        # Simulate the status being changed by another concurrent request
        booking.update_column(:status, 'deposit_paid')
      end

      post :submit_deposit, params: {
        id: rental_booking.id,
        signature_name: 'John Doe',
        signature_data: 'data:image/png;base64,AAAA'
      }

      # Should redirect to booking page with notice, NOT create a new checkout session
      expect(response).to redirect_to(rental_booking_path(rental_booking))
      expect(flash[:notice]).to eq('Deposit has already been paid.')
      expect(ClientDocuments::DepositService).not_to have_received(:new)
    end
  end

  describe 'deposit_success action' do
    let(:user) { create(:user, :client, email: customer.email) }

    before do
      sign_in user
    end

    it 'renders success page without changing booking status' do
      original_status = rental_booking.status

      get :deposit_success, params: { id: rental_booking.id }

      expect(response).to have_http_status(:success)
      expect(rental_booking.reload.status).to eq(original_status)
    end
  end

  describe 'deposit_cancel action' do
    let(:user) { create(:user, :client, email: customer.email) }

    before do
      sign_in user
    end

    it 'redirects to booking page with notice' do
      get :deposit_cancel, params: { id: rental_booking.id }

      expect(response).to redirect_to(rental_booking_path(rental_booking))
      expect(flash[:notice]).to eq('Payment was cancelled. You can try again when ready.')
    end
  end
end
