require 'rails_helper'

RSpec.describe ClientDocuments::ExperienceBookingProcessor do
  let(:business) { create(:business) }
  let(:customer) { create(:tenant_customer, business: business) }
  let(:service) do
    create(
      :service,
      business: business,
      service_type: :experience,
      price: 75.0,
      duration: 60,
      min_bookings: 1,
      max_bookings: 10,
      spots: 20
    )
  end
  let(:staff_member) { create(:staff_member, business: business) }
  let(:product) { create(:product, business: business) }
  let(:product_variant) { create(:product_variant, product: product) }
  let(:metadata) do
    {
      'booking_payload' => {
        'service_id' => service.id,
        'staff_member_id' => staff_member.id,
        'service_variant_id' => nil,
        'start_time' => 2.days.from_now.iso8601,
        'end_time' => (2.days.from_now + 1.hour).iso8601,
        'notes' => 'Excited for this!',
        'tenant_customer_id' => customer.id,
        'quantity' => 2,
        'booking_product_add_ons' => [
          { 'product_variant_id' => product_variant.id, 'quantity' => 1 }
        ]
      }
    }
  end
  let(:document) do
    create(
      :client_document,
      business: business,
      tenant_customer: customer,
      documentable: customer,
      document_type: 'experience_booking',
      status: 'pending_payment',
      metadata: metadata
    )
  end
  let(:payment) { create(:payment, business: business, tenant_customer: customer, amount: 150.0, stripe_payment_intent_id: 'pi_123', status: :completed) }
  let(:session_data) { { 'customer' => 'cus_123', 'payment_intent' => 'pi_123' } }

  before do
    ActsAsTenant.current_tenant = business
    allow(NotificationService).to receive(:invoice_payment_confirmation)
    allow(NotificationService).to receive(:business_new_booking)
    allow(NotificationService).to receive(:business_payment_received)
    allow(NotificationService).to receive(:booking_confirmation)
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  it 'creates a booking, invoice, and links payment when payload is present' do
    expect {
      described_class.process!(document: document, payment: payment, session: session_data)
    }.to change { Booking.count }.by(1)

    booking = Booking.last
    expect(booking.service).to eq(service)
    expect(booking.booking_product_add_ons.count).to eq(1)

    payment.reload
    document.reload

    expect(payment.invoice).to eq(booking.invoice)
    expect(document.documentable).to eq(booking)
    expect(document.metadata['booking_id']).to eq(booking.id)
  end

  it 'no-ops when booking payload is missing' do
    document.update!(metadata: {})

    expect {
      described_class.process!(document: document, payment: payment, session: session_data)
    }.not_to change { Booking.count }
  end

  it 'is idempotent when invoked multiple times for the same document' do
    described_class.process!(document: document, payment: payment, session: session_data)
    document.reload
    original_booking_id = document.metadata['booking_id']

    expect {
      described_class.process!(document: document, payment: payment, session: session_data)
    }.not_to change { Booking.count }

    document.reload
    expect(document.metadata['booking_id']).to eq(original_booking_id)
    expect(document.documentable_id).to eq(original_booking_id)
  end

  it 'applies promo code usage when present in the payload' do
    metadata['booking_payload']['applied_promo_code'] = 'SAVE50'
    metadata['booking_payload']['promo_code_type'] = 'fixed'
    metadata['booking_payload']['promo_discount_amount'] = 20.0
    document.update!(metadata: metadata)

    allow(PromoCodeService).to receive(:apply_code).and_return(success: true)

    described_class.process!(document: document, payment: payment, session: session_data)

    expect(PromoCodeService).to have_received(:apply_code).with(
      'SAVE50',
      business,
      kind_of(Booking),
      customer
    )
  end
end
