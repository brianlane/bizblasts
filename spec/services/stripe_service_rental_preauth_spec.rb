# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StripeService, type: :service do
  let(:business) do
    create(:business,
      stripe_account_id: 'acct_test123',
      rental_deposit_preauth_enabled: true
    )
  end

  let(:customer) { create(:tenant_customer, business: business) }
  let(:product) { create(:product, :rental, business: business, security_deposit: 100.00) }

  let(:rental_booking) do
    create(:rental_booking,
      business: business,
      product: product,
      tenant_customer: customer,
      security_deposit_amount: 100.00
    )
  end

  describe '.create_rental_deposit_checkout_session with preauth' do
    let(:success_url) { 'https://example.com/success' }
    let(:cancel_url) { 'https://example.com/cancel' }

    before do
      allow(StripeService).to receive(:configure_stripe_api_key)
      allow(StripeService).to receive(:ensure_stripe_customer_for_tenant)
        .and_return(double(id: 'cus_test123'))
    end

    context 'when business has preauth enabled' do
      it 'creates checkout session with manual capture mode' do
        expect(Stripe::Checkout::Session).to receive(:create) do |params, options|
          expect(params[:payment_intent_data][:capture_method]).to eq('manual')
          expect(params[:metadata][:preauth_enabled]).to be true
          expect(options[:stripe_account]).to eq(business.stripe_account_id)

          double(id: 'cs_test123', url: 'https://checkout.stripe.com/test')
        end

        session = StripeService.create_rental_deposit_checkout_session(
          rental_booking: rental_booking,
          success_url: success_url,
          cancel_url: cancel_url
        )

        expect(session).to be_present
      end
    end

    context 'when business has preauth disabled' do
      before do
        business.update!(rental_deposit_preauth_enabled: false)
      end

      it 'creates checkout session without manual capture mode' do
        expect(Stripe::Checkout::Session).to receive(:create) do |params, options|
          expect(params[:payment_intent_data][:capture_method]).to be_nil
          expect(params[:metadata][:preauth_enabled]).to be false

          double(id: 'cs_test123', url: 'https://checkout.stripe.com/test')
        end

        session = StripeService.create_rental_deposit_checkout_session(
          rental_booking: rental_booking,
          success_url: success_url,
          cancel_url: cancel_url
        )

        expect(session).to be_present
      end
    end
  end

  describe '.capture_rental_deposit_authorization' do
    before do
      rental_booking.update!(deposit_authorization_id: 'pi_test_auth_123')
      allow(StripeService).to receive(:configure_stripe_api_key)
    end

    it 'captures the authorized payment intent' do
      mock_payment_intent = double(id: 'pi_test_auth_123', status: 'succeeded')

      expect(Stripe::PaymentIntent).to receive(:capture)
        .with('pi_test_auth_123', { stripe_account: business.stripe_account_id })
        .and_return(mock_payment_intent)

      result = StripeService.capture_rental_deposit_authorization(rental_booking)

      expect(result[:success]).to be true
      expect(result[:payment_intent]).to eq(mock_payment_intent)
    end

    it 'returns error when no authorization_id present' do
      rental_booking.update!(deposit_authorization_id: nil)

      result = StripeService.capture_rental_deposit_authorization(rental_booking)

      expect(result[:success]).to be false
      expect(result[:error]).to eq('No authorization ID found for this rental booking')
    end

    it 'returns error when deposit already captured' do
      rental_booking.update!(deposit_captured_at: Time.current)

      result = StripeService.capture_rental_deposit_authorization(rental_booking)

      expect(result[:success]).to be false
      expect(result[:error]).to eq('Deposit has already been captured')
    end

    it 'handles Stripe InvalidRequestError' do
      allow(Stripe::PaymentIntent).to receive(:capture)
        .and_raise(Stripe::InvalidRequestError.new('Payment intent already captured', 'pi'))

      result = StripeService.capture_rental_deposit_authorization(rental_booking)

      expect(result[:success]).to be false
      expect(result[:error]).to include('already captured')
    end

    it 'handles Stripe StripeError' do
      allow(Stripe::PaymentIntent).to receive(:capture)
        .and_raise(Stripe::StripeError.new('Connection error'))

      result = StripeService.capture_rental_deposit_authorization(rental_booking)

      expect(result[:success]).to be false
      expect(result[:error]).to eq('Connection error')
    end

    it 'handles unexpected errors' do
      allow(Stripe::PaymentIntent).to receive(:capture)
        .and_raise(StandardError.new('Unexpected error'))

      result = StripeService.capture_rental_deposit_authorization(rental_booking)

      expect(result[:success]).to be false
      expect(result[:error]).to eq('Unexpected error')
    end
  end

  describe '.cancel_rental_deposit_authorization' do
    before do
      rental_booking.update!(deposit_authorization_id: 'pi_test_auth_123')
      allow(StripeService).to receive(:configure_stripe_api_key)
    end

    it 'cancels the authorized payment intent' do
      mock_payment_intent = double(id: 'pi_test_auth_123', status: 'canceled')

      expect(Stripe::PaymentIntent).to receive(:cancel)
        .with('pi_test_auth_123', { stripe_account: business.stripe_account_id })
        .and_return(mock_payment_intent)

      result = StripeService.cancel_rental_deposit_authorization(rental_booking)

      expect(result[:success]).to be true
      expect(result[:payment_intent]).to eq(mock_payment_intent)
    end

    it 'returns error when no authorization_id present' do
      rental_booking.update!(deposit_authorization_id: nil)

      result = StripeService.cancel_rental_deposit_authorization(rental_booking)

      expect(result[:success]).to be false
      expect(result[:error]).to eq('No authorization ID found for this rental booking')
    end

    it 'returns error when deposit already captured' do
      rental_booking.update!(deposit_captured_at: Time.current)

      result = StripeService.cancel_rental_deposit_authorization(rental_booking)

      expect(result[:success]).to be false
      expect(result[:error]).to eq('Cannot cancel - deposit has already been captured')
    end

    it 'returns error when authorization already released' do
      rental_booking.update!(deposit_authorization_released_at: Time.current)

      result = StripeService.cancel_rental_deposit_authorization(rental_booking)

      expect(result[:success]).to be false
      expect(result[:error]).to eq('Authorization has already been released')
    end

    it 'handles Stripe InvalidRequestError' do
      allow(Stripe::PaymentIntent).to receive(:cancel)
        .and_raise(Stripe::InvalidRequestError.new('Payment intent already captured', 'pi'))

      result = StripeService.cancel_rental_deposit_authorization(rental_booking)

      expect(result[:success]).to be false
      expect(result[:error]).to include('already captured')
    end

    it 'handles Stripe StripeError' do
      allow(Stripe::PaymentIntent).to receive(:cancel)
        .and_raise(Stripe::StripeError.new('Connection error'))

      result = StripeService.cancel_rental_deposit_authorization(rental_booking)

      expect(result[:success]).to be false
      expect(result[:error]).to eq('Connection error')
    end
  end

  describe '.handle_rental_deposit_payment_completion with preauth' do
    let(:session_data) do
      {
        'id' => 'cs_test123',
        'payment_intent' => 'pi_test_auth_123',
        'customer' => 'cus_test123',
        'metadata' => {
          'type' => 'rental_deposit',
          'business_id' => business.id.to_s,
          'rental_booking_id' => rental_booking.id.to_s,
          'customer_id' => customer.id.to_s,
          'booking_number' => rental_booking.booking_number,
          'preauth_enabled' => 'true'
        }
      }
    end

    before do
      ActsAsTenant.current_tenant = nil
    end

    it 'marks deposit as authorized when preauth is enabled' do
      expect {
        StripeService.handle_rental_deposit_payment_completion(session_data)
      }.to change { rental_booking.reload.status }.from('pending_deposit').to('deposit_paid')
        .and change { rental_booking.deposit_authorization_id }.from(nil).to('pi_test_auth_123')
        .and change { rental_booking.deposit_authorized_at }.from(nil)
    end

    it 'marks deposit as paid when preauth is disabled' do
      session_data['metadata']['preauth_enabled'] = 'false'

      expect {
        StripeService.handle_rental_deposit_payment_completion(session_data)
      }.to change { rental_booking.reload.status }.from('pending_deposit').to('deposit_paid')
        .and change { rental_booking.stripe_deposit_payment_intent_id }.from(nil).to('pi_test_auth_123')
        .and change { rental_booking.deposit_paid_at }.from(nil)
    end
  end
end
