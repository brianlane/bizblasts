require 'rails_helper'

RSpec.describe SmsRateLimiter, type: :service do
  let(:business) { create(:business, sms_enabled: true) }
  let(:customer) { create(:tenant_customer, business: business, phone: '+15551234567', skip_notification_email: true) }

  before do
    allow(Rails.application.config).to receive(:sms_enabled).and_return(true)
  end

  describe '.can_send?' do
    context 'when business SMS is disabled' do
      before do
        allow(business).to receive(:can_send_sms?).and_return(false)
      end

      it 'returns false' do
        expect(SmsRateLimiter.can_send?(business, customer)).to be false
      end
    end

    context 'when within all limits' do
      it 'returns true' do
        expect(SmsRateLimiter.can_send?(business, customer)).to be true
      end
    end

    context 'when business daily limit is exceeded' do
      before do
        # Mock aggregated counts to return daily limit exceeded
        allow(SmsRateLimiter).to receive(:get_aggregated_counts).with(business, customer).and_return({
          business_daily: SmsRateLimiter::MAX_SMS_PER_BUSINESS_PER_DAY,
          business_hourly: 50,
          customer_daily: 5,
          customer_hourly: 2
        })
      end

      it 'returns false' do
        expect(SmsRateLimiter.can_send?(business, customer)).to be false
      end

      it 'logs the rate limit warning' do
        expect(Rails.logger).to receive(:warn).with(/daily limit/)
        SmsRateLimiter.can_send?(business, customer)
      end
    end

    context 'when business hourly limit is exceeded' do
      before do
        # Mock aggregated counts to return hourly limit exceeded (100)
        allow(SmsRateLimiter).to receive(:get_aggregated_counts).with(business, customer).and_return({
          business_daily: 200,
          business_hourly: 100,
          customer_daily: 5,
          customer_hourly: 2
        })
      end

      it 'returns false' do
        expect(SmsRateLimiter.can_send?(business, customer)).to be false
      end

      it 'logs the rate limit warning' do
        expect(Rails.logger).to receive(:warn).with(/hourly limit/)
        SmsRateLimiter.can_send?(business, customer)
      end
    end

    context 'when customer daily limit is exceeded' do
      before do
        # Mock aggregated counts to return customer daily limit exceeded (10)
        allow(SmsRateLimiter).to receive(:get_aggregated_counts).with(business, customer).and_return({
          business_daily: 200,
          business_hourly: 50,
          customer_daily: 10,
          customer_hourly: 2
        })
      end

      it 'returns false' do
        expect(SmsRateLimiter.can_send?(business, customer)).to be false
      end

      it 'logs the customer rate limit warning' do
        expect(Rails.logger).to receive(:warn).with(/Customer.*daily limit/)
        SmsRateLimiter.can_send?(business, customer)
      end
    end

    context 'when customer hourly limit is exceeded' do
      before do
        # Mock aggregated counts to return customer hourly limit exceeded (5)
        allow(SmsRateLimiter).to receive(:get_aggregated_counts).with(business, customer).and_return({
          business_daily: 200,
          business_hourly: 50,
          customer_daily: 8,
          customer_hourly: 5
        })
      end

      it 'returns false' do
        expect(SmsRateLimiter.can_send?(business, customer)).to be false
      end

      it 'logs the customer hourly rate limit warning' do
        expect(Rails.logger).to receive(:warn).with(/Customer.*hourly limit/)
        SmsRateLimiter.can_send?(business, customer)
      end
    end

    context 'when sms is disabled on the business' do
      it 'returns false' do
        business.update!(sms_enabled: false)
        expect(SmsRateLimiter.can_send?(business, customer)).to be false
      end
    end

    context 'when no customer provided' do
      it 'only checks business limits' do
        expect(SmsRateLimiter.can_send?(business, nil)).to be true
      end

      it 'still respects business daily limits' do
        allow(SmsRateLimiter).to receive(:get_aggregated_counts).with(business, nil).and_return({
          business_daily: SmsRateLimiter::MAX_SMS_PER_BUSINESS_PER_DAY,
          business_hourly: 50,
          customer_daily: 0,
          customer_hourly: 0
        })
        expect(SmsRateLimiter.can_send?(business, nil)).to be false
      end
    end
  end

  describe '.record_send' do
    it 'logs the SMS send record' do
      allow(Rails.logger).to receive(:info)
      expect(Rails.logger).to receive(:info).with("[SMS_RATE_LIMIT] Recorded SMS send")
      expect(Rails.logger).to receive(:info).with(/Recorded SMS send for business.*customer/)
      SmsRateLimiter.record_send(business, customer)
    end

    context 'when no customer provided' do
      it 'logs without customer information' do
        allow(Rails.logger).to receive(:info)
        expect(Rails.logger).to receive(:info).with("[SMS_RATE_LIMIT] Recorded SMS send")
        expect(Rails.logger).to receive(:info).with(/Recorded SMS send for business.*#{business.id}$/)
        SmsRateLimiter.record_send(business, nil)
      end
    end
  end

  describe 'private methods' do
    describe '.business_daily_count' do
      it 'counts SMS messages for business within current day' do
        # Create messages from different times
        create(:sms_message, business: business, created_at: 2.days.ago)
        create_list(:sms_message, 3, business: business, created_at: Time.current)
        # Ensure this message is definitely today by using beginning of day + some hours
        create(:sms_message, business: business, created_at: Date.current.beginning_of_day + 6.hours)
        
        count = SmsRateLimiter.send(:business_daily_count, business)
        expect(count).to eq(4) # Only today's messages
      end
    end

    describe '.business_hourly_count' do
      it 'counts SMS messages for business within last hour' do
        create(:sms_message, business: business, created_at: 2.hours.ago)
        create_list(:sms_message, 2, business: business, created_at: 30.minutes.ago)
        create(:sms_message, business: business, created_at: Time.current)
        
        count = SmsRateLimiter.send(:business_hourly_count, business)
        expect(count).to eq(3) # Only last hour's messages
      end
    end
  end
end