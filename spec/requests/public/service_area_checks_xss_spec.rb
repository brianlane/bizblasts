# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public::ServiceAreaChecksController XSS Protection", type: :request do
  let(:business) { create(:business, :with_subdomain) }
  let(:service) { create(:service, business: business) }
  let(:booking_policy) { create(:booking_policy, business: business) }

  before do
    booking_policy # Ensure booking policy is created
    ActsAsTenant.with_tenant(business) do
      host! TenantHost.host_for(business, nil)
    end
  end

  describe "XSS Protection in safe_return_path" do
    describe "GET /service_area_check/new" do
      context "with dangerous javascript: scheme" do
        it "rejects javascript: URLs and uses fallback" do
          get new_service_area_check_path, params: { service_id: service.id, return_to: "javascript:alert('XSS')" }
          expect(response).to have_http_status(:success)
          expect(assigns(:return_to)).to eq(new_tenant_booking_path(service_id: service.id))
          expect(assigns(:return_to)).not_to include("javascript")
        end
      end

      context "with dangerous data: scheme" do
        it "rejects data: URLs and uses fallback" do
          get new_service_area_check_path, params: { service_id: service.id, return_to: "data:text/html,<script>alert('XSS')</script>" }
          expect(response).to have_http_status(:success)
          expect(assigns(:return_to)).to eq(new_tenant_booking_path(service_id: service.id))
          expect(assigns(:return_to)).not_to include("data:")
        end
      end

      context "with dangerous vbscript: scheme" do
        it "rejects vbscript: URLs and uses fallback" do
          get new_service_area_check_path, params: { service_id: service.id, return_to: "vbscript:msgbox('XSS')" }
          expect(response).to have_http_status(:success)
          expect(assigns(:return_to)).to eq(new_tenant_booking_path(service_id: service.id))
          expect(assigns(:return_to)).not_to include("vbscript")
        end
      end

      context "with dangerous file: scheme" do
        it "rejects file: URLs and uses fallback" do
          get new_service_area_check_path, params: { service_id: service.id, return_to: "file:///etc/passwd" }
          expect(response).to have_http_status(:success)
          expect(assigns(:return_to)).to eq(new_tenant_booking_path(service_id: service.id))
          expect(assigns(:return_to)).not_to include("file:")
        end
      end

      context "with uppercase dangerous schemes (case insensitivity check)" do
        it "rejects JAVASCRIPT: URLs" do
          get new_service_area_check_path, params: { service_id: service.id, return_to: "JAVASCRIPT:alert('XSS')" }
          expect(response).to have_http_status(:success)
          expect(assigns(:return_to)).to eq(new_tenant_booking_path(service_id: service.id))
          expect(assigns(:return_to)).not_to include("JAVASCRIPT")
        end

        it "rejects DATA: URLs" do
          get new_service_area_check_path, params: { service_id: service.id, return_to: "DATA:text/html,<script>alert('XSS')</script>" }
          expect(response).to have_http_status(:success)
          expect(assigns(:return_to)).to eq(new_tenant_booking_path(service_id: service.id))
          expect(assigns(:return_to)).not_to include("DATA")
        end
      end

      context "with safe relative paths" do
        it "allows safe relative paths" do
          get new_service_area_check_path, params: { service_id: service.id, return_to: "/dashboard" }
          expect(response).to have_http_status(:success)
          expect(assigns(:return_to)).to eq("/dashboard")
        end

        it "allows relative paths with query strings" do
          get new_service_area_check_path, params: { service_id: service.id, return_to: "/bookings?status=pending" }
          expect(response).to have_http_status(:success)
          expect(assigns(:return_to)).to eq("/bookings?status=pending")
        end

        it "allows complex relative paths" do
          get new_service_area_check_path, params: { service_id: service.id, return_to: "/business_manager/settings/profile" }
          expect(response).to have_http_status(:success)
          expect(assigns(:return_to)).to eq("/business_manager/settings/profile")
        end
      end

      context "with external URLs (open redirect prevention)" do
        it "rejects http URLs with hosts" do
          get new_service_area_check_path, params: { service_id: service.id, return_to: "http://evil.com/phishing" }
          expect(response).to have_http_status(:success)
          expect(assigns(:return_to)).to eq(new_tenant_booking_path(service_id: service.id))
          expect(assigns(:return_to)).not_to include("evil.com")
        end

        it "rejects https URLs with hosts" do
          get new_service_area_check_path, params: { service_id: service.id, return_to: "https://evil.com/phishing" }
          expect(response).to have_http_status(:success)
          expect(assigns(:return_to)).to eq(new_tenant_booking_path(service_id: service.id))
          expect(assigns(:return_to)).not_to include("evil.com")
        end

        it "rejects protocol-relative URLs" do
          get new_service_area_check_path, params: { service_id: service.id, return_to: "//evil.com/phishing" }
          expect(response).to have_http_status(:success)
          expect(assigns(:return_to)).to eq(new_tenant_booking_path(service_id: service.id))
          expect(assigns(:return_to)).not_to include("evil.com")
        end
      end

      context "with malformed URLs" do
        it "rejects invalid URI syntax" do
          get new_service_area_check_path, params: { service_id: service.id, return_to: "ht!tp://invalid" }
          expect(response).to have_http_status(:success)
          expect(assigns(:return_to)).to eq(new_tenant_booking_path(service_id: service.id))
        end

        it "handles blank return_to gracefully" do
          get new_service_area_check_path, params: { service_id: service.id, return_to: "" }
          expect(response).to have_http_status(:success)
          expect(assigns(:return_to)).to eq(new_tenant_booking_path(service_id: service.id))
        end

        it "handles nil return_to gracefully" do
          get new_service_area_check_path, params: { service_id: service.id }
          expect(response).to have_http_status(:success)
          expect(assigns(:return_to)).to eq(new_tenant_booking_path(service_id: service.id))
        end
      end

      context "without service" do
        it "uses tenant_calendar_path as fallback" do
          get new_service_area_check_path, params: { return_to: "javascript:alert('XSS')" }
          expect(response).to have_http_status(:success)
          expect(assigns(:return_to)).to eq(tenant_calendar_path)
        end

        it "allows safe relative paths without service" do
          get new_service_area_check_path, params: { return_to: "/dashboard" }
          expect(response).to have_http_status(:success)
          expect(assigns(:return_to)).to eq("/dashboard")
        end
      end

      context "edge cases for XSS vectors" do
        it "handles URL-encoded strings safely (they remain encoded as safe paths)" do
          get new_service_area_check_path, params: { service_id: service.id, return_to: "javascript%3Aalert('XSS')" }
          expect(response).to have_http_status(:success)
          # URL encoding in query params stays encoded - it becomes a safe relative path
          # The browser won't execute "javascript%3Aalert" as JavaScript code
          result = assigns(:return_to)
          # This is actually safe because it stays URL-encoded and won't execute as JS
          expect(result).to eq("javascript%3Aalert('XSS')")
        end

        it "rejects mixed case javascript schemes" do
          get new_service_area_check_path, params: { service_id: service.id, return_to: "JaVaScRiPt:alert('XSS')" }
          expect(response).to have_http_status(:success)
          expect(assigns(:return_to)).to eq(new_tenant_booking_path(service_id: service.id))
        end

        it "rejects data URLs with base64" do
          get new_service_area_check_path, params: { service_id: service.id, return_to: "data:text/html;base64,PHNjcmlwdD5hbGVydCgnWFNTJyk8L3NjcmlwdD4=" }
          expect(response).to have_http_status(:success)
          expect(assigns(:return_to)).to eq(new_tenant_booking_path(service_id: service.id))
        end
      end
    end

    describe "POST /service_area_check" do
      let(:valid_params) do
        {
          service_id: service.id,
          return_to: "/dashboard",
          service_area_check: { zip: "85001" }
        }
      end

      before do
        allow_any_instance_of(ServiceAreaChecker).to receive(:within_radius?).and_return(true)
      end

      it "sanitizes return_to on successful check" do
        post service_area_check_path, params: valid_params.merge(return_to: "javascript:alert('XSS')")
        expect(response).to redirect_to(new_tenant_booking_path(service_id: service.id))
        expect(response.location).not_to include("javascript")
      end

      it "allows safe return_to on successful check" do
        post service_area_check_path, params: valid_params
        expect(response).to redirect_to("/dashboard")
      end

      it "sanitizes return_to on validation error" do
        post service_area_check_path, params: valid_params.merge(
          return_to: "data:text/html,<script>alert('XSS')</script>",
          service_area_check: { zip: "" }
        )
        expect(response).to have_http_status(:unprocessable_entity)
        expect(assigns(:return_to)).not_to include("data:")
        expect(assigns(:return_to)).to eq(new_tenant_booking_path(service_id: service.id))
      end
    end
  end
end
