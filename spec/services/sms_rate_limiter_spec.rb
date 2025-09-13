require 'rails_helper'

RSpec.describe SmsRateLimiter, type: :service do
  let(:business) { create(:business, sms_enabled: true, tier: 'standard') }
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
        # Create SMS messages to reach the daily limit for standard tier (500)
        create_list(:sms_message, 500, business: business, created_at: Time.current)
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
        # Create SMS messages to reach the hourly limit (100)
        create_list(:sms_message, 100, business: business, created_at: 30.minutes.ago)
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
        # Create SMS messages to reach customer daily limit (10)
        create_list(:sms_message, 10, 
                   business: business, 
                   tenant_customer: customer,
                   created_at: Time.current)
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
        # Create SMS messages to reach customer hourly limit (5)
        create_list(:sms_message, 5, 
                   business: business, 
                   tenant_customer: customer,
                   created_at: 30.minutes.ago)
      end

      it 'returns false' do
        expect(SmsRateLimiter.can_send?(business, customer)).to be false
      end

      it 'logs the customer hourly rate limit warning' do
        expect(Rails.logger).to receive(:warn).with(/Customer.*hourly limit/)
        SmsRateLimiter.can_send?(business, customer)
      end
    end

    context 'with different business tiers' do
      it 'respects premium tier daily limits' do
        business.update!(tier: 'premium')
        # Create messages spread across different hours to avoid hourly limit
        create_list(:sms_message, 99, business: business, created_at: 10.hours.ago)
        create_list(:sms_message, 99, business: business, created_at: 9.hours.ago)
        create_list(:sms_message, 99, business: business, created_at: 8.hours.ago)
        create_list(:sms_message, 99, business: business, created_at: 7.hours.ago)
        create_list(:sms_message, 99, business: business, created_at: 6.hours.ago)
        create_list(:sms_message, 99, business: business, created_at: 5.hours.ago)
        create_list(:sms_message, 99, business: business, created_at: 4.hours.ago)
        create_list(:sms_message, 99, business: business, created_at: 3.hours.ago)
        create_list(:sms_message, 99, business: business, created_at: 2.hours.ago)
        create_list(:sms_message, 99, business: business, created_at: 2.hours.ago) # 999 total, under 1000 limit
        
        expect(SmsRateLimiter.can_send?(business, customer)).to be true
      end

      it 'respects free tier daily limits' do
        business.update!(tier: 'free')
        # Create messages spread across different hours to avoid hourly limit
        create_list(:sms_message, 33, business: business, created_at: 10.hours.ago)
        create_list(:sms_message, 33, business: business, created_at: 8.hours.ago)
        create_list(:sms_message, 33, business: business, created_at: 6.hours.ago) # 99 total
        
        expect(SmsRateLimiter.can_send?(business, customer)).to be true
        
        create(:sms_message, business: business, created_at: 4.hours.ago) # 100th message hits the limit
        expect(SmsRateLimiter.can_send?(business, customer)).to be false
      end
    end

    context 'when no customer provided' do
      it 'only checks business limits' do
        expect(SmsRateLimiter.can_send?(business, nil)).to be true
      end

      it 'still respects business daily limits' do
        create_list(:sms_message, 500, business: business, created_at: Time.current)
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
        create(:sms_message, business: business, created_at: 2.hours.ago)
        
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