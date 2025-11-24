# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Stripe invoice payment webhooks', type: :request do
  include ActiveJob::TestHelper

  let!(:business) { create(:business, stripe_account_id: 'acct_test123') }
  let!(:customer) { create(:tenant_customer, business: business) }
  let!(:invoice)  { create(:invoice, business: business, tenant_customer: customer, status: :pending) }
  let!(:payment)  { create(:payment, business: business, invoice: invoice, tenant_customer: customer, status: :pending, stripe_payment_intent_id: 'pi_test123') }
  let(:signature) { 'test_sig' }

  before do
    # Mock Rails credentials for webhook secret (required by middleware)
    allow(Rails.application.credentials).to receive(:dig).with(:stripe, :webhook_secret).and_return('whsec_test_secret')
  end

  def send_webhook!(event_type)
    payload = {
      id: 'evt_test',
      type: event_type,
      account: business.stripe_account_id,
      data: {
        object: {
          id: 'pi_test123',
          metadata: {
            business_id: business.id.to_s,
            invoice_id: invoice.id.to_s
          },
          charges: { data: [{ payment_method_details: { type: 'card' } }] }
        }
      }
    }.to_json

    allow(Stripe::Webhook).to receive(:construct_event).and_return(
      Stripe::Event.construct_from(JSON.parse(payload))
    )

    post '/webhooks/stripe', params: payload, headers: { 'CONTENT_TYPE' => 'application/json', 'Stripe-Signature' => signature }
  end

  context 'successful payment' do
    it 'marks invoice paid and enqueues confirmation email' do
      perform_enqueued_jobs do
        expect {
          send_webhook!('payment_intent.succeeded')
        }.to change { performed_jobs.select { _1[:job] == ActionMailer::MailDeliveryJob }.count }.by(1)
      end

      expect(response).to have_http_status(:ok)
      expect(invoice.reload.status).to eq('paid')
      expect(payment.reload.status).to eq('completed')
    end
  end

  context 'failed payment' do
    it 'marks payment failed and leaves invoice pending' do
      perform_enqueued_jobs do
        send_webhook!('payment_intent.payment_failed')
      end

      expect(response).to have_http_status(:ok)
      expect(payment.reload.status).to eq('failed')
      expect(invoice.reload.status).to eq('pending')
    end
  end

  context 'retry succeeds after failure' do
    it 'transitions from failed -> completed' do
      perform_enqueued_jobs { send_webhook!('payment_intent.payment_failed') }
      expect(payment.reload.status).to eq('failed')

      perform_enqueued_jobs { send_webhook!('payment_intent.succeeded') }

      expect(payment.reload.status).to eq('completed')
      expect(invoice.reload.status).to eq('paid')
    end
  end
end 