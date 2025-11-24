# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SmsNotificationReplayJob, type: :job do
  let(:business) { create(:business, sms_enabled: true, tier: 'premium') }
  let(:customer) { create(:tenant_customer, business: business, phone: '+15551234567', phone_opt_in: true, phone_opt_in_at: Time.current, skip_notification_email: true) }

  describe '#perform' do
    context 'with valid customer and pending notifications' do
      let!(:notification) { create(:pending_sms_notification, business: business, tenant_customer: customer) }

      before do
        allow(SmsNotificationReplayService).to receive(:replay_for_customer).and_return({
          total: 1,
          sent: 1,
          failed: 0,
          expired: 0,
          rate_limited: 0
        })
      end

      it 'calls replay service for customer' do
        expect(SmsNotificationReplayService).to receive(:replay_for_customer).with(customer, nil)
        described_class.new.perform(customer.id, nil, 0)
      end

      it 'logs job start' do
        expect(Rails.logger).to receive(:info).with("[SMS_REPLAY_JOB] Starting job for customer #{customer.id}, business all, retry 0")
        allow(Rails.logger).to receive(:info) # Allow other log statements
        described_class.new.perform(customer.id, nil, 0)
      end

      it 'logs job completion' do
        expect(Rails.logger).to receive(:info).with("[SMS_REPLAY_JOB] Completed for customer #{customer.id}: {total: 1, sent: 1, failed: 0, expired: 0, rate_limited: 0}")
        allow(Rails.logger).to receive(:info) # Allow other log statements
        described_class.new.perform(customer.id, nil, 0)
      end
    end

    context 'with business-specific replay' do
      let!(:notification) { create(:pending_sms_notification, business: business, tenant_customer: customer) }

      before do
        allow(SmsNotificationReplayService).to receive(:replay_for_customer).and_return({
          total: 1,
          sent: 1,
          failed: 0,
          expired: 0,
          rate_limited: 0
        })
      end

      it 'calls replay service with specific business' do
        expect(SmsNotificationReplayService).to receive(:replay_for_customer).with(customer, business)
        described_class.new.perform(customer.id, business.id, 0)
      end

      it 'logs business-specific replay' do
        expect(Rails.logger).to receive(:info).with("[SMS_REPLAY_JOB] Starting job for customer #{customer.id}, business #{business.id}, retry 0")
        allow(Rails.logger).to receive(:info)
        described_class.new.perform(customer.id, business.id, 0)
      end
    end

    context 'when customer is not opted in' do
      before do
        customer.update!(phone_opt_in: false)
      end

      it 'skips replay' do
        expect(SmsNotificationReplayService).not_to receive(:replay_for_customer)
        described_class.new.perform(customer.id, nil, 0)
      end

      it 'logs warning' do
        expect(Rails.logger).to receive(:warn).with("[SMS_REPLAY_JOB] Customer #{customer.id} is not opted in for SMS, skipping replay")
        allow(Rails.logger).to receive(:info)
        described_class.new.perform(customer.id, nil, 0)
      end
    end

    context 'when customer is opted out from specific business' do
      before do
        customer.opt_out_from_business!(business)
      end

      it 'skips business-specific replay' do
        expect(SmsNotificationReplayService).not_to receive(:replay_for_customer)
        described_class.new.perform(customer.id, business.id, 0)
      end

      it 'logs warning' do
        expect(Rails.logger).to receive(:warn).with("[SMS_REPLAY_JOB] Customer #{customer.id} is opted out from business #{business.id}, skipping replay")
        allow(Rails.logger).to receive(:info)
        described_class.new.perform(customer.id, business.id, 0)
      end
    end

    context 'when customer not found' do
      it 'raises RecordNotFound error' do
        expect {
          described_class.new.perform(99999, nil, 0)
        }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it 'logs error' do
        expect(Rails.logger).to receive(:error).with("[SMS_REPLAY_JOB] Record not found: Couldn't find TenantCustomer with 'id'=99999")
        allow(Rails.logger).to receive(:info)

        expect {
          described_class.new.perform(99999, nil, 0)
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context 'with rate-limited notifications' do
      before do
        allow(SmsNotificationReplayService).to receive(:replay_for_customer).and_return({
          total: 3,
          sent: 1,
          failed: 0,
          expired: 0,
          rate_limited: 2
        })
      end

      it 'schedules retry job with delay' do
        expect(described_class).to receive(:set).with(wait: 15.minutes).and_return(described_class)
        expect(described_class).to receive(:perform_later).with(customer.id, nil, 1)
        described_class.new.perform(customer.id, nil, 0)
      end

      it 'logs retry scheduling' do
        allow(described_class).to receive(:set).and_return(described_class)
        allow(described_class).to receive(:perform_later)
        expect(Rails.logger).to receive(:info).with("[SMS_REPLAY_JOB] Scheduling retry 1 for 2 rate-limited notifications in 900")
        allow(Rails.logger).to receive(:info)
        described_class.new.perform(customer.id, nil, 0)
      end
    end

    context 'retry delay calculation' do
      let(:job) { described_class.new }

      before do
        allow(SmsNotificationReplayService).to receive(:replay_for_customer).and_return({
          total: 1,
          sent: 0,
          failed: 0,
          expired: 0,
          rate_limited: 1
        })
      end

      it 'uses 15 minutes delay for first retry' do
        allow(described_class).to receive(:set).and_return(described_class)
        allow(described_class).to receive(:perform_later)
        delay = job.send(:calculate_retry_delay, 0)
        expect(delay).to eq(15.minutes)
      end

      it 'uses 1 hour delay for second retry' do
        delay = job.send(:calculate_retry_delay, 1)
        expect(delay).to eq(1.hour)
      end

      it 'uses 4 hours delay for third retry' do
        delay = job.send(:calculate_retry_delay, 2)
        expect(delay).to eq(4.hours)
      end

      it 'uses 12 hours delay for fourth retry' do
        delay = job.send(:calculate_retry_delay, 3)
        expect(delay).to eq(12.hours)
      end

      it 'uses 24 hours delay for final retry' do
        delay = job.send(:calculate_retry_delay, 4)
        expect(delay).to eq(24.hours)
      end
    end

    context 'with max retries reached' do
      let!(:notification) { create(:pending_sms_notification, business: business, tenant_customer: customer) }

      before do
        allow(SmsNotificationReplayService).to receive(:replay_for_customer).and_return({
          total: 1,
          sent: 0,
          failed: 0,
          expired: 0,
          rate_limited: 1
        })
      end

      it 'does not schedule another retry' do
        expect(described_class).not_to receive(:set)
        expect(described_class).not_to receive(:perform_later)
        described_class.new.perform(customer.id, nil, 5)
      end

      it 'marks abandoned notifications as failed' do
        described_class.new.perform(customer.id, nil, 5)

        expect(notification.reload.status).to eq('failed')
        expect(notification.failure_reason).to include('Abandoned after max retries')
      end

      it 'logs max retries reached' do
        allow(Rails.logger).to receive(:info) # Allow other info logs
        allow(Rails.logger).to receive(:error) # Allow other error logs
        expect(Rails.logger).to receive(:error).with("[SMS_REPLAY_JOB] Max retries (5) reached for customer #{customer.id}, abandoning 1 rate-limited notifications")
        expect(Rails.logger).to receive(:warn).with(/Marked \d+ notifications as failed/)
        described_class.new.perform(customer.id, nil, 5)
      end
    end

    context 'with generic error' do
      before do
        allow(SmsNotificationReplayService).to receive(:replay_for_customer).and_raise(StandardError, 'Unexpected error')
      end

      it 'logs error' do
        expect(Rails.logger).to receive(:error).with("[SMS_REPLAY_JOB] Error processing customer #{customer.id}: Unexpected error")
        expect(Rails.logger).to receive(:error) # For backtrace
        allow(Rails.logger).to receive(:info)

        expect {
          described_class.new.perform(customer.id, nil, 0)
        }.to raise_error(StandardError)
      end

      it 'raises error for retry' do
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:error)

        expect {
          described_class.new.perform(customer.id, nil, 0)
        }.to raise_error(StandardError, 'Unexpected error')
      end
    end
  end

  describe '.schedule_for_customer' do
    it 'enqueues job with customer id' do
      expect {
        described_class.schedule_for_customer(customer)
      }.to have_enqueued_job(described_class).with(customer.id, nil, 0)
    end

    it 'enqueues job with customer and business id' do
      expect {
        described_class.schedule_for_customer(customer, business)
      }.to have_enqueued_job(described_class).with(customer.id, business.id, 0)
    end

    it 'logs scheduling' do
      expect(Rails.logger).to receive(:info).with("[SMS_REPLAY_JOB] Scheduled replay for customer #{customer.id}, business all")
      described_class.schedule_for_customer(customer)
    end

    it 'logs business-specific scheduling' do
      expect(Rails.logger).to receive(:info).with("[SMS_REPLAY_JOB] Scheduled replay for customer #{customer.id}, business #{business.id}")
      described_class.schedule_for_customer(customer, business)
    end
  end

  describe '.schedule_for_customer_delayed' do
    before do
      # Stub set and perform_later for ActiveJob API
      allow(described_class).to receive(:set).and_return(described_class)
      allow(described_class).to receive(:perform_later)
    end

    it 'calls set with delay and perform_later' do
      expect(described_class).to receive(:set).with(wait: 2.hours).and_return(described_class)
      expect(described_class).to receive(:perform_later).with(customer.id, business.id, 0)
      described_class.schedule_for_customer_delayed(customer, business, delay: 2.hours)
    end

    it 'uses default 1 hour delay' do
      expect(described_class).to receive(:set).with(wait: 1.hour).and_return(described_class)
      expect(described_class).to receive(:perform_later).with(customer.id, nil, 0)
      described_class.schedule_for_customer_delayed(customer)
    end

    it 'logs delayed scheduling' do
      expect(Rails.logger).to receive(:info).with("[SMS_REPLAY_JOB] Scheduled delayed replay (3600) for customer #{customer.id}, business all")
      described_class.schedule_for_customer_delayed(customer)
    end
  end

  describe '#mark_abandoned_notifications_as_failed' do
    let(:job) { described_class.new }
    let!(:notification1) { create(:pending_sms_notification, business: business, tenant_customer: customer) }
    let!(:notification2) { create(:pending_sms_notification, business: business, tenant_customer: customer) }

    it 'marks all pending notifications as failed' do
      job.send(:mark_abandoned_notifications_as_failed, customer, nil)

      expect(notification1.reload.status).to eq('failed')
      expect(notification2.reload.status).to eq('failed')
      expect(notification1.failure_reason).to include('Abandoned after max retries')
      expect(notification2.failure_reason).to include('Abandoned after max retries')
    end

    it 'only marks notifications for specific business when provided' do
      other_business = create(:business, sms_enabled: true, tier: 'premium')
      other_customer = create(:tenant_customer, business: other_business, phone: customer.phone, skip_notification_email: true)
      other_notification = create(:pending_sms_notification, business: other_business, tenant_customer: other_customer)

      job.send(:mark_abandoned_notifications_as_failed, customer, business)

      expect(notification1.reload.status).to eq('failed')
      expect(other_notification.reload.status).to eq('pending')
    end

    it 'logs abandoned count' do
      expect(Rails.logger).to receive(:warn).with("[SMS_REPLAY_JOB] Marked 2 notifications as failed for customer #{customer.id} due to max retries")
      job.send(:mark_abandoned_notifications_as_failed, customer, nil)
    end

    it 'handles no pending notifications gracefully' do
      notification1.mark_as_sent!
      notification2.mark_as_sent!

      expect(Rails.logger).not_to receive(:warn)
      job.send(:mark_abandoned_notifications_as_failed, customer, nil)
    end
  end

  describe 'job configuration' do
    it 'is configured for default queue' do
      expect(described_class.new.queue_name).to eq('default')
    end
  end

  describe 'integration with SmsNotificationReplayService' do
    let!(:notification) { create(:pending_sms_notification, :booking_confirmation, business: business, tenant_customer: customer) }

    before do
      # Mock Twilio
      twilio_client = instance_double(Twilio::REST::Client)
      twilio_messages = double("Messages")
      twilio_response = double("MessageResource", sid: "twilio-sid-123")

      allow(Twilio::REST::Client).to receive(:new).and_return(twilio_client)
      allow(twilio_client).to receive(:messages).and_return(twilio_messages)
      allow(twilio_messages).to receive(:create).and_return(twilio_response)

      # Mock template rendering
      allow(Sms::MessageTemplates).to receive(:render).and_return('Test message')

      # Mock rate limiter
      allow(SmsRateLimiter).to receive(:can_send?).and_return(true)
      allow(SmsRateLimiter).to receive(:record_send).and_return(true)

      # Enable SMS
      allow(Rails.application.config).to receive(:sms_enabled).and_return(true)
    end

    it 'successfully processes notifications through full stack' do
      described_class.new.perform(customer.id, nil, 0)

      expect(notification.reload.status).to eq('sent')
    end
  end
end
