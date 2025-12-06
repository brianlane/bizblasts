require 'rails_helper'

RSpec.describe 'Stripe client document webhooks', type: :request do
  include ActiveJob::TestHelper

  before do
    ActiveJob::Base.queue_adapter = :test
  end

  describe 'POST /webhooks/stripe' do
    it 'routes client document checkout completions through the experience processor' do
      business = create(:business)
      customer = create(:tenant_customer, business: business)
      service = create(:service, business: business, service_type: :experience, price: 125.0, duration: 60, min_bookings: 1, max_bookings: 10, spots: 10)
      staff_member = create(:staff_member, business: business)
      start_time = 2.days.from_now
      payload = {
        'service_id' => service.id,
        'staff_member_id' => staff_member.id,
        'service_variant_id' => nil,
        'start_time' => start_time.iso8601,
        'end_time' => (start_time + 1.hour).iso8601,
        'notes' => 'Excited for this!',
        'tenant_customer_id' => customer.id,
        'quantity' => 2,
        'booking_product_add_ons' => []
      }

      document = create(
        :client_document,
        business: business,
        tenant_customer: customer,
        document_type: 'experience_booking',
        status: 'pending_payment',
        documentable: nil,
        metadata: { 'booking_payload' => payload }
      )

      session_object = {
        'id' => 'cs_test_123',
        'payment_intent' => 'pi_123',
        'customer' => 'cus_456',
        'amount_total' => 2500,
        'metadata' => {
          'payment_type' => 'client_document',
          'client_document_id' => document.id,
          'business_id' => business.id
        }
      }

      webhook_payload = {
        'id' => 'evt_123',
        'type' => 'checkout.session.completed',
        'data' => { 'object' => session_object }
      }

      event_object = Stripe::Event.construct_from(webhook_payload)
      allow(Stripe::Webhook).to receive(:construct_event).and_return(event_object)

      expect(ClientDocuments::ExperienceBookingProcessor).to receive(:process!).with(
        hash_including(document: document, payment: kind_of(Payment), session: hash_including('payment_intent' => 'pi_123'))
      ).and_call_original

      perform_enqueued_jobs do
        post '/webhooks/stripe', params: webhook_payload.to_json, headers: { 'Stripe-Signature' => 't=123,v1=test' }
      end

      document.reload
      expect(document).to be_completed
    end
  end
end
