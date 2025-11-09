require 'rails_helper'

RSpec.describe 'SMS short links', type: :request do
  describe 'GET /s/:short_code' do
    around do |example|
      previous_setting = ActionController::Base.raise_on_open_redirects
      ActionController::Base.raise_on_open_redirects = true
      example.run
    ensure
      ActionController::Base.raise_on_open_redirects = previous_setting
    end

    it 'redirects to the stored URL across hosts when open redirects are enforced' do
      original_url = 'https://acme.bizblasts.com/manage/bookings'
      sms_link = create(:sms_link,
                        original_url: original_url,
                        short_code: 'abc123xy',
                        click_count: 0,
                        last_clicked_at: nil)

      expect {
        get "/s/#{sms_link.short_code}"
      }.to change { sms_link.reload.click_count }.from(0).to(1)

      expect(response).to have_http_status(:moved_permanently)
      expect(response.headers['Location']).to eq(original_url)
      expect(sms_link.last_clicked_at).to be_within(1.second).of(Time.current)
    end

    it 'falls back to root when the short code is unknown' do
      allow(Rails.logger).to receive(:warn)

      get '/s/missing123'

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq('Link not found')
      expect(Rails.logger).to have_received(:warn).with(/\[SMS_LINK\] Short code not found: missing123/)
    end

    it 'rejects stored URLs that are not http(s)' do
      sms_link = create(:sms_link,
                        original_url: 'javascript:alert(1)',
                        short_code: 'unsafe123',
                        click_count: 0,
                        last_clicked_at: nil)
      allow(Rails.logger).to receive(:warn)

      expect {
        get "/s/#{sms_link.short_code}"
      }.not_to change { sms_link.reload.click_count }

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq('Link not found')
      expect(Rails.logger).to have_received(:warn).with(/\[SMS_LINK\] Unsafe redirect attempted/)
    end
  end
end

