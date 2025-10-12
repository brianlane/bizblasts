# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SmsLinkShortener do
  describe '.shorten' do
    let(:original_url) { 'https://example.com/bookings/123/confirm' }
    let(:tracking_params) { { business_id: 1, customer_id: 2, notification_type: 'booking_confirmation' } }

    context 'in test environment' do
      it 'returns original URL without creating SmsLink' do
        expect {
          result = described_class.shorten(original_url, tracking_params)
          expect(result).to eq(original_url)
        }.not_to change(SmsLink, :count)
      end

      it 'does not create database record' do
        expect(SmsLink).not_to receive(:create!)
        described_class.shorten(original_url)
      end
    end

    context 'in development environment' do
      before do
        allow(Rails.env).to receive(:test?).and_return(false)
        allow(Rails.env).to receive(:development?).and_return(true)
        allow(Rails.env).to receive(:production?).and_return(false)
      end

      it 'returns original URL without creating SmsLink' do
        expect {
          result = described_class.shorten(original_url, tracking_params)
          expect(result).to eq(original_url)
        }.not_to change(SmsLink, :count)
      end
    end

    context 'in production environment' do
      before do
        allow(Rails.env).to receive(:test?).and_return(false)
        allow(Rails.env).to receive(:development?).and_return(false)
        allow(Rails.env).to receive(:production?).and_return(true)
      end

      it 'creates a shortened URL' do
        shortened = described_class.shorten(original_url, tracking_params)
        expect(shortened).to start_with('https://bizblasts.com/s/')
        expect(shortened.length).to be < original_url.length
      end

      it 'creates SmsLink record' do
        expect {
          described_class.shorten(original_url, tracking_params)
        }.to change(SmsLink, :count).by(1)
      end

      it 'stores original URL in SmsLink' do
        described_class.shorten(original_url, tracking_params)
        link = SmsLink.last
        expect(link.original_url).to eq(original_url)
      end

      it 'stores tracking params' do
        described_class.shorten(original_url, tracking_params)
        link = SmsLink.last
        expect(link.tracking_params).to eq(tracking_params.deep_stringify_keys)
      end

      it 'generates unique short code' do
        shortened = described_class.shorten(original_url, tracking_params)
        short_code = shortened.split('/').last

        expect(short_code).to be_present
        expect(short_code.length).to eq(8)
        expect(short_code).to match(/\A[a-z0-9]{8}\z/)
      end

      it 'extracts and stores short code from URL' do
        shortened = described_class.shorten(original_url, tracking_params)
        short_code = shortened.split('/').last

        link = SmsLink.last
        expect(link.short_code).to eq(short_code)
      end

      it 'enforces short code uniqueness' do
        # Create first link
        first_shortened = described_class.shorten(original_url, tracking_params)
        first_code = first_shortened.split('/').last

        # Mock SecureRandom to return duplicate code first, then unique code
        allow(SecureRandom).to receive(:alphanumeric).with(8)
          .and_return(first_code.upcase, first_code.upcase, 'unique123')

        # Create second link - should get different code
        second_shortened = described_class.shorten('https://example.com/other', {})
        second_code = second_shortened.split('/').last

        expect(second_code).not_to eq(first_code)
      end

      it 'uses https protocol in production' do
        shortened = described_class.shorten(original_url, tracking_params)
        expect(shortened).to start_with('https://')
      end

      it 'uses bizblasts.com domain in production' do
        shortened = described_class.shorten(original_url, tracking_params)
        expect(shortened).to include('bizblasts.com')
      end

      it 'handles empty tracking params' do
        shortened = described_class.shorten(original_url)
        link = SmsLink.last
        expect(link.tracking_params).to eq({})
      end

      it 'initializes click count to zero' do
        described_class.shorten(original_url, tracking_params)
        link = SmsLink.last
        expect(link.click_count).to eq(0)
      end

      it 'does not set last_clicked_at initially' do
        described_class.shorten(original_url, tracking_params)
        link = SmsLink.last
        expect(link.last_clicked_at).to be_nil
      end
    end

    context 'error handling' do
      before do
        allow(Rails.env).to receive(:test?).and_return(false)
        allow(Rails.env).to receive(:development?).and_return(false)
        allow(Rails.env).to receive(:production?).and_return(true)
      end

      context 'when SmsLink creation fails' do
        before do
          allow(SmsLink).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new)
        end

        it 'returns original URL as fallback' do
          result = described_class.shorten(original_url, tracking_params)
          expect(result).to eq(original_url)
        end

        it 'logs the error' do
          expect(Rails.logger).to receive(:error).with(/Failed to shorten URL/)
          described_class.shorten(original_url, tracking_params)
        end

        it 'does not raise exception' do
          expect {
            described_class.shorten(original_url, tracking_params)
          }.not_to raise_error
        end
      end

      context 'when database is unavailable' do
        before do
          allow(SmsLink).to receive(:create!).and_raise(ActiveRecord::ConnectionNotEstablished)
        end

        it 'falls back to original URL' do
          result = described_class.shorten(original_url, tracking_params)
          expect(result).to eq(original_url)
        end

        it 'logs error with details' do
          expect(Rails.logger).to receive(:error).with(a_string_matching(/Failed to shorten URL.*#{Regexp.escape(original_url)}/))
          described_class.shorten(original_url, tracking_params)
        end
      end

      context 'with invalid URL' do
        let(:invalid_url) { 'not-a-valid-url' }

        before do
          allow(Rails.env).to receive(:test?).and_return(false)
          allow(Rails.env).to receive(:production?).and_return(true)
        end

        it 'still attempts to shorten' do
          # Service doesn't validate URL format, just shortens it
          expect {
            described_class.shorten(invalid_url, tracking_params)
          }.to change(SmsLink, :count).by(1)
        end
      end
    end
  end

  describe '.expand' do
    let(:original_url) { 'https://example.com/bookings/123/confirm' }
    let(:short_code) { 'abc12345' }
    let!(:sms_link) do
      create(:sms_link,
             original_url: original_url,
             short_code: short_code,
             click_count: 0,
             last_clicked_at: nil)
    end

    context 'with valid short code' do
      it 'returns original URL' do
        result = described_class.expand(short_code)
        expect(result).to eq(original_url)
      end

      it 'increments click count' do
        expect {
          described_class.expand(short_code)
        }.to change { sms_link.reload.click_count }.from(0).to(1)
      end

      it 'increments click count on subsequent clicks' do
        described_class.expand(short_code)
        described_class.expand(short_code)
        described_class.expand(short_code)

        expect(sms_link.reload.click_count).to eq(3)
      end

      it 'updates last_clicked_at timestamp' do
        expect {
          described_class.expand(short_code)
        }.to change { sms_link.reload.last_clicked_at }.from(nil)

        expect(sms_link.last_clicked_at).to be_within(1.second).of(Time.current)
      end

      it 'updates last_clicked_at on each click' do
        first_click_time = nil

        travel_to Time.current do
          described_class.expand(short_code)
          first_click_time = sms_link.reload.last_clicked_at
        end

        travel_to 1.hour.from_now do
          described_class.expand(short_code)
          second_click_time = sms_link.reload.last_clicked_at

          expect(second_click_time).to be > first_click_time
          expect(second_click_time).to be_within(1.second).of(Time.current)
        end
      end
    end

    context 'with invalid short code' do
      it 'returns nil for non-existent code' do
        result = described_class.expand('invalid99')
        expect(result).to be_nil
      end

      it 'does not raise error' do
        expect {
          described_class.expand('invalid99')
        }.not_to raise_error
      end

      it 'does not affect existing links' do
        expect {
          described_class.expand('invalid99')
        }.not_to change { sms_link.reload.click_count }
      end
    end

    context 'with empty short code' do
      it 'returns nil' do
        result = described_class.expand('')
        expect(result).to be_nil
      end
    end

    context 'with nil short code' do
      it 'returns nil' do
        result = described_class.expand(nil)
        expect(result).to be_nil
      end
    end

    context 'tracking analytics' do
      let!(:link_with_tracking) do
        create(:sms_link,
               original_url: 'https://example.com/page',
               short_code: 'tracked1',
               click_count: 5,
               last_clicked_at: 2.days.ago,
               tracking_params: { business_id: 1, campaign: 'sms_reminder' })
      end

      it 'preserves tracking params when expanding' do
        described_class.expand('tracked1')

        expect(link_with_tracking.reload.tracking_params['business_id']).to eq(1)
        expect(link_with_tracking.reload.tracking_params['campaign']).to eq('sms_reminder')
      end

      it 'increments from existing click count' do
        expect {
          described_class.expand('tracked1')
        }.to change { link_with_tracking.reload.click_count }.from(5).to(6)
      end

      it 'updates last_clicked_at even if previously clicked' do
        old_time = link_with_tracking.last_clicked_at

        travel_to Time.current do
          described_class.expand('tracked1')
          new_time = link_with_tracking.reload.last_clicked_at

          expect(new_time).to be > old_time
          expect(new_time).to be_within(1.second).of(Time.current)
        end
      end
    end

    context 'concurrent clicks' do
      it 'handles multiple simultaneous expansions' do
        threads = 5.times.map do
          Thread.new { described_class.expand(short_code) }
        end
        threads.each(&:join)

        expect(sms_link.reload.click_count).to eq(5)
      end
    end
  end

  describe 'integration scenarios' do
    context 'full lifecycle in production' do
      before do
        allow(Rails.env).to receive(:test?).and_return(false)
        allow(Rails.env).to receive(:development?).and_return(false)
        allow(Rails.env).to receive(:production?).and_return(true)
      end

      it 'shortens and expands URL correctly' do
        # Shorten URL
        tracking = { business_id: 42, customer_id: 99 }
        shortened_url = described_class.shorten('https://example.com/booking/confirm', tracking)

        # Extract short code
        short_code = shortened_url.split('/').last

        # Expand URL
        expanded_url = described_class.expand(short_code)

        expect(expanded_url).to eq('https://example.com/booking/confirm')
      end

      it 'tracks analytics through full lifecycle' do
        tracking = { campaign: 'booking_reminder', sent_at: Time.current.iso8601 }
        shortened_url = described_class.shorten('https://example.com/page', tracking)
        short_code = shortened_url.split('/').last

        # Simulate multiple clicks
        3.times { described_class.expand(short_code) }

        link = SmsLink.find_by(short_code: short_code)
        expect(link.click_count).to eq(3)
        expect(link.tracking_params['campaign']).to eq('booking_reminder')
        expect(link.last_clicked_at).to be_within(1.second).of(Time.current)
      end
    end

    context 'multiple links for same original URL' do
      before do
        allow(Rails.env).to receive(:test?).and_return(false)
        allow(Rails.env).to receive(:production?).and_return(true)
      end

      it 'creates separate short links' do
        url = 'https://example.com/same-page'

        first_shortened = described_class.shorten(url, { customer: 1 })
        second_shortened = described_class.shorten(url, { customer: 2 })

        expect(first_shortened).not_to eq(second_shortened)
        expect(SmsLink.where(original_url: url).count).to eq(2)
      end

      it 'tracks clicks independently' do
        url = 'https://example.com/same-page'

        first_shortened = described_class.shorten(url, { customer: 1 })
        second_shortened = described_class.shorten(url, { customer: 2 })

        first_code = first_shortened.split('/').last
        second_code = second_shortened.split('/').last

        # Click first link 3 times
        3.times { described_class.expand(first_code) }

        # Click second link 2 times
        2.times { described_class.expand(second_code) }

        first_link = SmsLink.find_by(short_code: first_code)
        second_link = SmsLink.find_by(short_code: second_code)

        expect(first_link.click_count).to eq(3)
        expect(second_link.click_count).to eq(2)
      end
    end

    context 'SMS character savings' do
      before do
        allow(Rails.env).to receive(:test?).and_return(false)
        allow(Rails.env).to receive(:production?).and_return(true)
      end

      it 'significantly reduces URL length' do
        long_url = 'https://example.com/business/bookings/123/confirm?token=abc123xyz789&redirect=dashboard'
        shortened = described_class.shorten(long_url)

        expect(shortened.length).to be < long_url.length
        expect(long_url.length - shortened.length).to be > 20
      end

      it 'keeps URL under 30 characters for SMS optimization' do
        url = 'https://example.com/very/long/path/to/resource'
        shortened = described_class.shorten(url)

        # Short URL format: https://bizblasts.com/s/abc12345
        expect(shortened.length).to be < 40
      end
    end
  end

  describe 'edge cases' do
    context 'with special characters in tracking params' do
      before do
        allow(Rails.env).to receive(:test?).and_return(false)
        allow(Rails.env).to receive(:production?).and_return(true)
      end

      it 'handles special characters in tracking data' do
        tracking = {
          message: "Customer's appointment",
          data: { 'key' => 'value with spaces' }
        }

        shortened = described_class.shorten('https://example.com', tracking)
        link = SmsLink.last

        expect(link.tracking_params['message']).to eq("Customer's appointment")
      end
    end

    context 'with very long URLs' do
      before do
        allow(Rails.env).to receive(:test?).and_return(false)
        allow(Rails.env).to receive(:production?).and_return(true)
      end

      it 'handles URLs with many query parameters' do
        long_url = 'https://example.com/page?' + (1..20).map { |i| "param#{i}=value#{i}" }.join('&')

        expect {
          shortened = described_class.shorten(long_url)
          expect(shortened).to be_present
        }.to change(SmsLink, :count).by(1)
      end
    end

    context 'with URL containing fragments' do
      before do
        allow(Rails.env).to receive(:test?).and_return(false)
        allow(Rails.env).to receive(:production?).and_return(true)
      end

      it 'preserves URL fragments' do
        url_with_fragment = 'https://example.com/page#section-2'
        described_class.shorten(url_with_fragment)

        link = SmsLink.last
        expect(link.original_url).to eq(url_with_fragment)
      end
    end
  end
end
