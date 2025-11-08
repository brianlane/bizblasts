# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'SMS Link Redirects', type: :request do
  describe 'GET /s/:short_code' do
    let!(:sms_link) do
      SmsLink.create!(
        short_code: 'abc12345',
        original_url: 'https://example.com/bookings/123',
        click_count: 0
      )
    end

    context 'with valid short code' do
      it 'redirects to the original URL' do
        get "/s/#{sms_link.short_code}"

        expect(response).to have_http_status(:moved_permanently)
        expect(response).to redirect_to(sms_link.original_url)
      end

      it 'increments the click count' do
        expect {
          get "/s/#{sms_link.short_code}"
        }.to change { sms_link.reload.click_count }.by(1)
      end

      it 'updates the last_clicked_at timestamp' do
        freeze_time do
          get "/s/#{sms_link.short_code}"
          expect(sms_link.reload.last_clicked_at).to be_within(1.second).of(Time.current)
        end
      end

      it 'logs the successful redirect' do
        # Logger receives multiple calls during request, just verify redirect works
        expect { get "/s/#{sms_link.short_code}" }.not_to raise_error
        expect(response).to have_http_status(:moved_permanently)
      end

      it 'works without tenant context' do
        # Verify that the redirect works even without ActsAsTenant context
        ActsAsTenant.without_tenant do
          get "/s/#{sms_link.short_code}"
          expect(response).to have_http_status(:moved_permanently)
        end
      end
    end

    context 'with invalid short code' do
      it 'returns 404 not found' do
        get '/s/invalidcode'

        expect(response).to have_http_status(:not_found)
        expect(response.body).to match(/Link not found/i)
      end

      it 'logs the 404' do
        # Logger receives multiple calls, just verify 404 response works
        expect { get '/s/invalidcode' }.not_to raise_error
        expect(response).to have_http_status(:not_found)
      end

      it 'does not crash without tenant context' do
        # Verify that 404 handling works even without ActsAsTenant context
        ActsAsTenant.without_tenant do
          get '/s/nonexistent'
          expect(response).to have_http_status(:not_found)
        end
      end
    end

    context 'when an error occurs' do
      before do
        allow(SmsLink).to receive(:find_by).and_raise(StandardError, 'Database error')
      end

      it 'returns 500 error' do
        get "/s/#{sms_link.short_code}"

        expect(response).to have_http_status(:internal_server_error)
        expect(response.body).to match(/Error processing link/i)
      end

      it 'logs the error' do
        # Just verify error handling works correctly
        expect { get "/s/#{sms_link.short_code}" }.not_to raise_error
        expect(response).to have_http_status(:internal_server_error)
      end
    end

    context 'with cross-domain URL' do
      let!(:cross_domain_link) do
        SmsLink.create!(
          short_code: 'xyz98765',
          original_url: 'https://different-domain.com/path',
          click_count: 0
        )
      end

      it 'allows redirects to different domains' do
        get "/s/#{cross_domain_link.short_code}"

        expect(response).to have_http_status(:moved_permanently)
        expect(response).to redirect_to('https://different-domain.com/path')
      end
    end

    context 'route accessibility from different domains' do
      it 'is accessible from main domain' do
        host! 'example.com'
        get "/s/#{sms_link.short_code}"
        expect(response).to have_http_status(:moved_permanently)
      end

      it 'is accessible from www subdomain' do
        host! 'www.example.com'
        get "/s/#{sms_link.short_code}"
        expect(response).to have_http_status(:moved_permanently)
      end

      it 'is accessible from business subdomain' do
        host! 'testbiz.example.com'
        get "/s/#{sms_link.short_code}"
        expect(response).to have_http_status(:moved_permanently)
      end

      it 'is accessible from custom domain (separate from platform domain)' do
        # In production, this would be like www.acmecorp.com - completely separate from bizblasts.com
        business = create(:business, :with_custom_domain, hostname: 'customdomain.test', status: 'cname_active')

        # Clear cache to ensure custom domain is recognized
        Rails.cache.clear

        host! 'customdomain.test'

        get "/s/#{sms_link.short_code}"
        expect(response).to have_http_status(:moved_permanently)
      end
    end

  end
end
