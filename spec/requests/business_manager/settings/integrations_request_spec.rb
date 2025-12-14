require 'rails_helper'

RSpec.describe "BusinessManager::Settings::Integrations", type: :request do
  let(:business) { create(:business) }
  let(:business_manager_user) { create(:user, :manager, business: business) }

  before do
    host! "#{business.hostname}.lvh.me"
    ActsAsTenant.current_tenant = business
    sign_in business_manager_user
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe "GET /index" do
    it "renders a successful response" do
      get business_manager_settings_integrations_path
      expect(response).to be_successful
    end

    it "includes Google Business integration UI" do
      get business_manager_settings_integrations_path
      expect(response.body).to include("Google Business Reviews")
      expect(response.body).to include("ADP Payroll Export")
    end
  end

  describe "PATCH /adp-payroll/config" do
    it "updates payroll export configuration" do
      patch adp_payroll_config_update_business_manager_settings_integrations_path, params: {
        adp_payroll_export_config: {
          active: true,
          rounding_minutes: 10,
          round_total_hours: true,
          config: {
            default_pay_code: 'REG',
            timezone: 'UTC',
            included_booking_statuses: ['completed']
          }
        }
      }

      expect(response).to redirect_to(business_manager_settings_integrations_path)
      cfg = business.reload.adp_payroll_export_config
      expect(cfg).to be_present
      expect(cfg.rounding_minutes).to eq(10)
      expect(cfg.config['default_pay_code']).to eq('REG')
    end
  end

  describe "ADP preview" do
    it "renders a payroll preview table when requested" do
      staff = create(:staff_member, business: business, adp_employee_id: 'E123', adp_pay_code: 'REG')
      create(:booking, :completed, business: business, staff_member: staff, start_time: Time.utc(2025, 12, 1, 10), end_time: Time.utc(2025, 12, 1, 11))

      get business_manager_settings_integrations_path, params: {
        adp_preview: '1',
        adp_range_start: '2025-12-01',
        adp_range_end: '2025-12-01'
      }

      expect(response).to be_successful
      expect(response.body).to include('Payroll preview')
      expect(response.body).to include('E123')
    end
  end

  describe "POST /adp-payroll/exports" do
    it "enqueues a payroll export job" do
      expect {
        post adp_payroll_export_create_business_manager_settings_integrations_path, params: {
          range_start: '2025-12-01',
          range_end: '2025-12-07'
        }
      }.to have_enqueued_job(Payroll::GenerateAdpExportJob)

      expect(response).to redirect_to(business_manager_settings_integrations_path)
    end
  end

  describe "QuickBooks actions" do
    before do
      business.create_quickbooks_connection!(realm_id: '123', access_token: 'x', refresh_token: 'y', active: true, config: {})
    end

    it "updates QuickBooks config" do
      patch quickbooks_config_update_business_manager_settings_integrations_path, params: {
        quickbooks: {
          income_account_id: '42',
          default_sales_item_name: 'BizBlasts Sales',
          customer_strategy: 'single',
          update_existing_invoices: '1'
        }
      }

      expect(response).to redirect_to(business_manager_settings_integrations_path)
      cfg = business.reload.quickbooks_connection.config
      expect(cfg['income_account_id']).to eq('42')
      expect(cfg['customer_strategy']).to eq('single')
    end

    it "allows update_existing_invoices to be turned off" do
      # Turn it on
      patch quickbooks_config_update_business_manager_settings_integrations_path, params: {
        quickbooks: { update_existing_invoices: '1' }
      }
      expect(business.reload.quickbooks_connection.config['update_existing_invoices']).to eq(true)

      # Turn it off (checkbox unchecked; hidden field posts '0')
      patch quickbooks_config_update_business_manager_settings_integrations_path, params: {
        quickbooks: { update_existing_invoices: '0' }
      }
      expect(business.reload.quickbooks_connection.config['update_existing_invoices']).to eq(false)
    end

    it "enqueues QuickBooks invoice export job" do
      expect {
        post quickbooks_export_invoices_business_manager_settings_integrations_path, params: {
          range_start: '2025-12-01',
          range_end: '2025-12-07',
          invoice_statuses: ['paid'],
          export_payments: '1'
        }
      }.to have_enqueued_job(Quickbooks::ExportInvoicesJob)

      expect(response).to redirect_to(business_manager_settings_integrations_path)
    end
  end

  describe "POST /lookup-place-id" do
    let(:valid_google_maps_url) { "https://www.google.com/maps/place/My+Business/@40.7128,-74.0060,17z" }

    before do
      Rails.cache.delete("place_id_extraction:user:#{business_manager_user.id}")
    end

    context "with valid URL" do
      it "accepts valid google.com URL" do
        post lookup_place_id_business_manager_settings_integrations_path, params: { input: valid_google_maps_url }
        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['job_id']).to be_present
      end

      it "accepts valid google.co.uk URL" do
        url = "https://www.google.co.uk/maps/place/My+Business/@51.5074,-0.1278,17z"
        post lookup_place_id_business_manager_settings_integrations_path, params: { input: url }
        expect(response).to have_http_status(:success)
      end
    end

    context "URL validation (security)" do
      it "rejects http:// URLs (must be HTTPS)" do
        url = "http://www.google.com/maps/place/My+Business"
        post lookup_place_id_business_manager_settings_integrations_path, params: { input: url }
        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json['error']).to include('Invalid Google Maps URL')
      end

      it "rejects URL injection attempts (subdomain attack)" do
        url = "https://google.com.evil.com/maps/place/My+Business"
        post lookup_place_id_business_manager_settings_integrations_path, params: { input: url }
        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json['error']).to include('Invalid Google Maps URL')
      end

      it "rejects URL injection attempts (path injection)" do
        url = "https://evil.com/google.com/maps/place/My+Business"
        post lookup_place_id_business_manager_settings_integrations_path, params: { input: url }
        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json['error']).to include('Invalid Google Maps URL')
      end

      it "rejects URLs without /maps/ in path" do
        url = "https://www.google.com/search?q=My+Business"
        post lookup_place_id_business_manager_settings_integrations_path, params: { input: url }
        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json['error']).to include('Invalid Google Maps URL')
      end

      it "rejects empty input" do
        post lookup_place_id_business_manager_settings_integrations_path, params: { input: "" }
        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json['error']).to include('Please enter a Google Maps URL')
      end

      it "rejects malformed URLs" do
        url = "not-a-valid-url"
        post lookup_place_id_business_manager_settings_integrations_path, params: { input: url }
        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json['error']).to include('Invalid Google Maps URL')
      end

      it "accepts valid URLs that contain unicode characters (smart quotes)" do
        url = "https://www.google.com/maps/place/Bee\u2019s+Best+Bet+Detail+%26+Protection/@33.3923204,-111.9279131,11z/data=!4m14!1m7!3m6!1s0x872b090d325f7fdb:0x79b31f1dbc0a282b!2sBee\u2019s+Best+Bet+Detail+%26+Protection!8m2!3d33.3923204!4d-111.927913!16s%2Fg%2F11q8vxdbtc!3m5!1s0x872b090d325f7fdb:0x79b31f1dbc0a282b!8m2!3d33.3923204!4d-111.927913!16s%2Fg%2F11q8vxdbtc"
        post lookup_place_id_business_manager_settings_integrations_path, params: { input: url }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['job_id']).to be_present
      end
    end

    context "rate limiting (security)" do
      it "allows up to 5 requests per hour" do
        5.times do
          post lookup_place_id_business_manager_settings_integrations_path, params: { input: valid_google_maps_url }
          expect(response).to have_http_status(:success)
        end
      end

      it "blocks 6th request within same hour" do
        5.times do
          post lookup_place_id_business_manager_settings_integrations_path, params: { input: valid_google_maps_url }
        end

        post lookup_place_id_business_manager_settings_integrations_path, params: { input: valid_google_maps_url }
        expect(response).to have_http_status(:too_many_requests)
        json = JSON.parse(response.body)
        expect(json['error']).to include('Rate limit exceeded')
        expect(json['error']).to include('5 Place IDs per hour')
      end

      it "resets rate limit after cache expiry" do
        5.times do
          post lookup_place_id_business_manager_settings_integrations_path, params: { input: valid_google_maps_url }
        end

        Rails.cache.delete("place_id_extraction:user:#{business_manager_user.id}")

        post lookup_place_id_business_manager_settings_integrations_path, params: { input: valid_google_maps_url }
        expect(response).to have_http_status(:success)
      end
    end
  end
end
