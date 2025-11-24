# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PendingSmsNotification, type: :model do
  let(:business) { create(:business, sms_enabled: true, tier: 'premium') }
  let(:customer) { create(:tenant_customer, business: business, phone: '+15551234567', skip_notification_email: true) }

  describe 'associations' do
    it { should belong_to(:business) }
    it { should belong_to(:tenant_customer) }
    it { should belong_to(:booking).optional }
    it { should belong_to(:invoice).optional }
    it { should belong_to(:order).optional }
  end

  describe 'validations' do
    subject { build(:pending_sms_notification, business: business, tenant_customer: customer) }

    it { should validate_presence_of(:notification_type) }
    it { should validate_presence_of(:sms_type) }
    it { should validate_presence_of(:template_data) }
    it { should validate_presence_of(:phone_number) }
    it { should validate_presence_of(:queued_at) }
    it { should validate_presence_of(:expires_at) }
    it { should validate_presence_of(:deduplication_key) }
    it { should validate_presence_of(:status) }
    it { should validate_uniqueness_of(:deduplication_key) }

    context 'phone number format' do
      it 'accepts valid phone numbers' do
        valid_phones = ['+15551234567', '+442071234567', '+33123456789']
        valid_phones.each do |phone|
          notification = build(:pending_sms_notification, phone_number: phone, business: business, tenant_customer: customer)
          expect(notification).to be_valid, "#{phone} should be valid"
        end
      end

      it 'rejects invalid phone numbers' do
        invalid_phones = ['invalid', '+0123', '123-456-7890', '0123456789']
        invalid_phones.each do |phone|
          notification = build(:pending_sms_notification, phone_number: phone, business: business, tenant_customer: customer)
          expect(notification).not_to be_valid, "#{phone} should be invalid"
        end
      end
    end

    context 'status validation' do
      it 'accepts valid statuses' do
        %w[pending sent failed expired].each do |status|
          notification = build(:pending_sms_notification, status: status, business: business, tenant_customer: customer)
          expect(notification).to be_valid
        end
      end

      it 'rejects invalid statuses' do
        expect {
          build(:pending_sms_notification, status: 'invalid_status', business: business, tenant_customer: customer)
        }.to raise_error(ArgumentError, /'invalid_status' is not a valid status/)
      end
    end
  end

  describe 'scopes' do
    let!(:pending_notification) { create(:pending_sms_notification, business: business, tenant_customer: customer, status: 'pending') }
    let!(:sent_notification) { create(:pending_sms_notification, :sent, business: business, tenant_customer: customer) }
    let!(:expired_notification) { create(:pending_sms_notification, :expired, business: business, tenant_customer: customer) }

    describe '.pending' do
      it 'returns only pending notifications' do
        expect(PendingSmsNotification.pending).to include(pending_notification)
        expect(PendingSmsNotification.pending).not_to include(sent_notification)
        expect(PendingSmsNotification.pending).not_to include(expired_notification)
      end
    end

    describe '.expired' do
      it 'returns only expired notifications' do
        expect(PendingSmsNotification.expired).to include(expired_notification)
        expect(PendingSmsNotification.expired).not_to include(pending_notification)
      end
    end

    describe '.not_expired' do
      it 'returns only non-expired notifications' do
        expect(PendingSmsNotification.not_expired).to include(pending_notification)
        expect(PendingSmsNotification.not_expired).to include(sent_notification)
        expect(PendingSmsNotification.not_expired).not_to include(expired_notification)
      end
    end

    describe '.for_customer' do
      let(:other_customer) { create(:tenant_customer, business: business, phone: '+15559876543', skip_notification_email: true) }
      let!(:other_notification) { create(:pending_sms_notification, business: business, tenant_customer: other_customer) }

      it 'returns notifications for specific customer' do
        expect(PendingSmsNotification.for_customer(customer)).to include(pending_notification)
        expect(PendingSmsNotification.for_customer(customer)).not_to include(other_notification)
      end
    end

    describe '.for_business' do
      let(:other_business) { create(:business, sms_enabled: true, tier: 'premium') }
      let(:other_business_customer) { create(:tenant_customer, business: other_business, phone: '+15559876543', skip_notification_email: true) }
      let!(:other_business_notification) { create(:pending_sms_notification, business: other_business, tenant_customer: other_business_customer) }

      it 'returns notifications for specific business' do
        expect(PendingSmsNotification.for_business(business)).to include(pending_notification)
        expect(PendingSmsNotification.for_business(business)).not_to include(other_business_notification)
      end
    end

    describe '.for_notification_type' do
      let!(:booking_notification) { create(:pending_sms_notification, :booking_confirmation, business: business, tenant_customer: customer) }
      let!(:invoice_notification) { create(:pending_sms_notification, :invoice_created, business: business, tenant_customer: customer) }

      it 'returns notifications of specific type' do
        expect(PendingSmsNotification.for_notification_type('booking_confirmation')).to include(booking_notification)
        expect(PendingSmsNotification.for_notification_type('booking_confirmation')).not_to include(invoice_notification)
      end
    end

    describe '.ready_for_processing' do
      it 'returns only pending, non-expired notifications ordered by queued_at' do
        results = PendingSmsNotification.ready_for_processing
        expect(results).to include(pending_notification)
        expect(results).not_to include(sent_notification)
        expect(results).not_to include(expired_notification)
      end
    end
  end

  describe '.queue_notification' do
    let(:template_data) { { service_name: 'Test Service', date: '01/01/2025' } }

    it 'creates a new pending notification' do
      expect {
        PendingSmsNotification.queue_notification(
          notification_type: 'booking_confirmation',
          customer: customer,
          business: business,
          sms_type: 'booking',
          template_data: template_data
        )
      }.to change(PendingSmsNotification, :count).by(1)
    end

    it 'sets correct attributes' do
      notification = PendingSmsNotification.queue_notification(
        notification_type: 'booking_confirmation',
        customer: customer,
        business: business,
        sms_type: 'booking',
        template_data: template_data
      )

      expect(notification.notification_type).to eq('booking_confirmation')
      expect(notification.sms_type).to eq('booking')
      expect(notification.business).to eq(business)
      expect(notification.tenant_customer).to eq(customer)
      expect(notification.phone_number).to eq(customer.phone)
      expect(notification.status).to eq('pending')
      expect(notification.expires_at).to be_within(1.second).of(7.days.from_now)
    end

    it 'generates a deduplication key' do
      notification = PendingSmsNotification.queue_notification(
        notification_type: 'booking_confirmation',
        customer: customer,
        business: business,
        sms_type: 'booking',
        template_data: template_data
      )

      expect(notification.deduplication_key).to be_present
      expect(notification.deduplication_key).to include('booking_confirmation')
      expect(notification.deduplication_key).to include(business.id.to_s)
      expect(notification.deduplication_key).to include(customer.id.to_s)
    end

    it 'prevents duplicate queuing' do
      first_notification = PendingSmsNotification.queue_notification(
        notification_type: 'booking_confirmation',
        customer: customer,
        business: business,
        sms_type: 'booking',
        template_data: template_data
      )

      # Try to queue the same notification again
      second_notification = PendingSmsNotification.queue_notification(
        notification_type: 'booking_confirmation',
        customer: customer,
        business: business,
        sms_type: 'booking',
        template_data: template_data
      )

      expect(first_notification.id).to eq(second_notification.id)
    end

    it 'allows re-queuing after notification is sent' do
      first_notification = PendingSmsNotification.queue_notification(
        notification_type: 'booking_confirmation',
        customer: customer,
        business: business,
        sms_type: 'booking',
        template_data: template_data
      )

      first_notification.mark_as_sent!

      second_notification = PendingSmsNotification.queue_notification(
        notification_type: 'booking_confirmation',
        customer: customer,
        business: business,
        sms_type: 'booking',
        template_data: template_data
      )

      expect(second_notification.id).not_to eq(first_notification.id)
      expect(second_notification.status).to eq('pending')
    end

    it 'includes optional associations in deduplication key' do
      service = create(:service, business: business)
      booking = create(:booking, business: business, tenant_customer: customer, service: service)

      notification = PendingSmsNotification.queue_notification(
        notification_type: 'booking_confirmation',
        customer: customer,
        business: business,
        sms_type: 'booking',
        template_data: template_data,
        booking: booking
      )

      expect(notification.deduplication_key).to include("booking:#{booking.id}")
      expect(notification.booking).to eq(booking)
    end
  end

  describe '.queue_booking_notification' do
    let(:service) { create(:service, business: business) }
    let(:booking) { create(:booking, business: business, tenant_customer: customer, service: service) }

    it 'creates a booking-specific notification' do
      notification = PendingSmsNotification.queue_booking_notification(
        'booking_confirmation',
        booking,
        { service_name: service.name }
      )

      expect(notification.notification_type).to eq('booking_confirmation')
      expect(notification.sms_type).to eq('booking')
      expect(notification.booking).to eq(booking)
      expect(notification.business).to eq(booking.business)
      expect(notification.tenant_customer).to eq(booking.tenant_customer)
    end
  end

  describe '.queue_invoice_notification' do
    let(:invoice) { create(:invoice, business: business, tenant_customer: customer) }

    it 'creates an invoice-specific notification' do
      notification = PendingSmsNotification.queue_invoice_notification(
        'invoice_created',
        invoice,
        { invoice_number: invoice.invoice_number }
      )

      expect(notification.notification_type).to eq('invoice_created')
      expect(notification.sms_type).to eq('payment')
      expect(notification.invoice).to eq(invoice)
      expect(notification.business).to eq(invoice.business)
      expect(notification.tenant_customer).to eq(invoice.tenant_customer)
    end
  end

  describe '.queue_order_notification' do
    let(:order) { create(:order, business: business, tenant_customer: customer) }

    it 'creates an order-specific notification' do
      notification = PendingSmsNotification.queue_order_notification(
        'order_confirmation',
        order,
        { order_number: order.order_number }
      )

      expect(notification.notification_type).to eq('order_confirmation')
      expect(notification.sms_type).to eq('order')
      expect(notification.order).to eq(order)
      expect(notification.business).to eq(order.business)
      expect(notification.tenant_customer).to eq(order.tenant_customer)
    end
  end

  describe '#mark_as_sent!' do
    let(:notification) { create(:pending_sms_notification, business: business, tenant_customer: customer) }

    it 'updates status to sent' do
      notification.mark_as_sent!
      expect(notification.status).to eq('sent')
    end

    it 'sets processed_at timestamp' do
      notification.mark_as_sent!
      expect(notification.processed_at).to be_present
      expect(notification.processed_at).to be_within(1.second).of(Time.current)
    end

    it 'clears failure fields' do
      notification.update!(failed_at: Time.current, failure_reason: 'Test error')
      notification.mark_as_sent!
      expect(notification.failed_at).to be_nil
      expect(notification.failure_reason).to be_nil
    end
  end

  describe '#mark_as_failed!' do
    let(:notification) { create(:pending_sms_notification, business: business, tenant_customer: customer) }
    let(:error_reason) { 'Customer not opted in' }

    it 'updates status to failed' do
      notification.mark_as_failed!(error_reason)
      expect(notification.status).to eq('failed')
    end

    it 'sets failed_at timestamp' do
      notification.mark_as_failed!(error_reason)
      expect(notification.failed_at).to be_present
      expect(notification.failed_at).to be_within(1.second).of(Time.current)
    end

    it 'records failure reason' do
      notification.mark_as_failed!(error_reason)
      expect(notification.failure_reason).to eq(error_reason)
    end
  end

  describe '#mark_as_expired!' do
    let(:notification) { create(:pending_sms_notification, business: business, tenant_customer: customer) }

    it 'updates status to expired' do
      notification.mark_as_expired!
      expect(notification.status).to eq('expired')
    end
  end

  describe '#expired?' do
    it 'returns true when expires_at is in the past' do
      notification = create(:pending_sms_notification, :expired, business: business, tenant_customer: customer)
      expect(notification.expired?).to be true
    end

    it 'returns false when expires_at is in the future' do
      notification = create(:pending_sms_notification, business: business, tenant_customer: customer, expires_at: 1.day.from_now)
      expect(notification.expired?).to be false
    end
  end

  describe '#age_in_days' do
    it 'calculates age in days since queued_at' do
      notification = create(:pending_sms_notification, business: business, tenant_customer: customer, queued_at: 3.days.ago)
      expect(notification.age_in_days).to be_within(0.1).of(3.0)
    end

    it 'returns fractional days for recent notifications' do
      notification = create(:pending_sms_notification, business: business, tenant_customer: customer, queued_at: 12.hours.ago)
      expect(notification.age_in_days).to be_within(0.1).of(0.5)
    end
  end

  describe '.cleanup_expired!' do
    let!(:expired_notification) { create(:pending_sms_notification, business: business, tenant_customer: customer, expires_at: 1.day.ago, status: 'pending') }
    let!(:valid_notification) { create(:pending_sms_notification, business: business, tenant_customer: customer, status: 'pending') }

    it 'marks expired notifications as expired' do
      expect {
        PendingSmsNotification.cleanup_expired!
      }.to change { expired_notification.reload.status }.from('pending').to('expired')
    end

    it 'does not affect non-expired notifications' do
      PendingSmsNotification.cleanup_expired!
      expect(valid_notification.reload.status).to eq('pending')
    end

    it 'returns count of expired notifications' do
      count = PendingSmsNotification.cleanup_expired!
      expect(count).to eq(1)
    end
  end

  describe '.stats' do
    let!(:pending_notification) { create(:pending_sms_notification, business: business, tenant_customer: customer, status: 'pending', queued_at: 2.days.ago) }
    let!(:recent_pending) { create(:pending_sms_notification, business: business, tenant_customer: customer, status: 'pending', queued_at: 1.hour.ago) }
    let!(:expired_notification) { create(:pending_sms_notification, :expired, business: business, tenant_customer: customer) }

    it 'returns correct statistics' do
      stats = PendingSmsNotification.stats

      expect(stats[:pending]).to eq(2)
      expect(stats[:total]).to be >= 3
      expect(stats[:oldest_pending]).to be_within(1.second).of(pending_notification.queued_at)
      expect(stats[:newest_pending]).to be_within(1.second).of(recent_pending.queued_at)
    end
  end

  describe 'deduplication key generation' do
    it 'includes notification type, business, and customer IDs' do
      notification = create(:pending_sms_notification, business: business, tenant_customer: customer)
      expect(notification.deduplication_key).to include('booking_confirmation')
      expect(notification.deduplication_key).to include(business.id.to_s)
      expect(notification.deduplication_key).to include(customer.id.to_s)
    end

    it 'includes time bucket for 24-hour window' do
      time_bucket = (Time.current.to_i / 24.hours).to_i
      notification = create(:pending_sms_notification, business: business, tenant_customer: customer)
      expect(notification.deduplication_key).to include(time_bucket.to_s)
    end

    it 'allows re-queuing after 24 hours' do
      # This test simulates time passing by creating different time buckets
      first_notification = nil
      first_key = nil

      travel_to Time.current do
        first_notification = create(:pending_sms_notification, business: business, tenant_customer: customer)
        first_key = first_notification.deduplication_key
      end

      travel_back

      travel_to 25.hours.from_now do
        second_notification = create(:pending_sms_notification, business: business, tenant_customer: customer)
        second_key = second_notification.deduplication_key

        expect(second_key).not_to eq(first_key)
      end

      travel_back
    end
  end
end
