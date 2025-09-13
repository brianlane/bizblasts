# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Webhooks::TwilioController", type: :request do
  let!(:tenant) { create(:business) }
  let!(:customer) { create(:tenant_customer, business: tenant, phone: "+15558675309") }
  let!(:marketing_campaign) { create(:marketing_campaign, name: "Test Campaign", business: tenant) }
  let!(:sms_message) { create(:sms_message, :sent, external_id: "twilio-sid-12345", marketing_campaign: marketing_campaign, tenant_customer: customer) }

  around do |example|
    ActsAsTenant.with_tenant(tenant) do
      example.run
    end
  end

  describe "POST /webhooks/twilio" do
    let(:valid_webhook_params) do
      {
        MessageSid: "twilio-sid-12345",
        MessageStatus: "delivered"
      }
    end

    let(:failed_webhook_params) do
      {
        MessageSid: "twilio-sid-12345",
        MessageStatus: "failed",
        ErrorCode: "30008"
      }
    end

    let(:invalid_webhook_params) do
      {
        MessageStatus: "delivered"
        # Missing MessageSid
      }
    end

    context "with valid webhook parameters" do
      before do
        allow(SmsService).to receive(:process_webhook).and_return({
          success: true,
          sms_message: sms_message,
          status: "delivered"
        })
      end

      it "processes the webhook successfully" do
        post "/webhooks/twilio", params: valid_webhook_params

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)).to include(
          "status" => "success",
          "message" => "Webhook processed"
        )
      end

      it "calls SmsService.process_webhook with correct parameters" do
        expect(SmsService).to receive(:process_webhook) do |params|
          expect(params[:MessageSid]).to eq("twilio-sid-12345")
          expect(params[:MessageStatus]).to eq("delivered")
          { success: true, sms_message: sms_message, status: "delivered" }
        end

        post "/webhooks/twilio", params: valid_webhook_params
      end

      it "logs the successful processing" do
        # Use a more specific expectation that filters out Rails internal logging
        expect(Rails.logger).to receive(:info).with(a_string_matching(/Received Twilio webhook/))
        expect(Rails.logger).to receive(:info).with("Twilio webhook processed successfully: delivered")
        allow(Rails.logger).to receive(:info) # Allow other Rails internal logging

        post "/webhooks/twilio", params: valid_webhook_params
        
        expect(response).to have_http_status(:ok)
      end
    end

    context "with failed message webhook" do
      before do
        allow(SmsService).to receive(:process_webhook).and_return({
          success: false,
          error: "Delivery failed (Code: 30008)",
          sms_message: sms_message
        })
      end

      it "handles failed message webhooks" do
        post "/webhooks/twilio", params: failed_webhook_params

        expect(response).to have_http_status(:unprocessable_content)
        expect(JSON.parse(response.body)).to include(
          "error" => "Delivery failed (Code: 30008)"
        )
      end

      it "logs the processing failure" do
        expect(Rails.logger).to receive(:info).with(a_string_matching(/Received Twilio webhook/))
        expect(Rails.logger).to receive(:error).with("Twilio webhook processing failed: Delivery failed (Code: 30008)")
        allow(Rails.logger).to receive(:info) # Allow other Rails internal logging

        post "/webhooks/twilio", params: failed_webhook_params
      end
    end

    context "with invalid webhook parameters" do
      before do
        allow(SmsService).to receive(:process_webhook).and_return({
          success: false,
          error: "Missing MessageSid in webhook"
        })
      end

      it "returns error for invalid parameters" do
        post "/webhooks/twilio", params: invalid_webhook_params

        expect(response).to have_http_status(:unprocessable_content)
        expect(JSON.parse(response.body)).to include(
          "error" => "Missing MessageSid in webhook"
        )
      end
    end

    context "when SmsService raises an exception" do
      before do
        allow(SmsService).to receive(:process_webhook).and_raise(StandardError.new("Database connection error"))
      end

      it "handles exceptions gracefully" do
        post "/webhooks/twilio", params: valid_webhook_params

        expect(response).to have_http_status(:internal_server_error)
        expect(JSON.parse(response.body)).to include(
          "error" => "Internal server error"
        )
      end

      it "logs the exception" do
        expect(Rails.logger).to receive(:info).with(a_string_matching(/Received Twilio webhook/))
        expect(Rails.logger).to receive(:error).with("Twilio webhook error: Database connection error")
        expect(Rails.logger).to receive(:error).with(a_string_matching(/.*\.rb:\d+/)) # Backtrace line
        allow(Rails.logger).to receive(:info) # Allow other Rails internal logging

        post "/webhooks/twilio", params: valid_webhook_params
      end
    end

    context "webhook signature verification" do
      before do
        # Mock production environment to enable signature verification
        allow(Rails.env).to receive(:production?).and_return(true)
      end

      context "with valid signature" do
        before do
          allow_any_instance_of(Webhooks::TwilioController).to receive(:valid_signature?).and_return(true)
          allow(SmsService).to receive(:process_webhook).and_return({
            success: true,
            sms_message: sms_message,
            status: "delivered"
          })
        end

        it "processes the webhook when signature is valid" do
          post "/webhooks/twilio", params: valid_webhook_params

          expect(response).to have_http_status(:ok)
        end
      end

      context "with invalid signature" do
        before do
          allow_any_instance_of(Webhooks::TwilioController).to receive(:valid_signature?).and_return(false)
        end

        it "rejects the webhook when signature is invalid" do
          post "/webhooks/twilio", params: valid_webhook_params

          expect(response).to have_http_status(:unauthorized)
          expect(JSON.parse(response.body)).to include(
            "error" => "Invalid signature"
          )
        end

        it "logs the invalid signature" do
          expect(Rails.logger).to receive(:info).with(a_string_matching(/Received Twilio webhook/))
          expect(Rails.logger).to receive(:error).with("Invalid Twilio webhook signature")
          allow(Rails.logger).to receive(:info) # Allow other Rails internal logging

          post "/webhooks/twilio", params: valid_webhook_params
        end
      end
    end
  end

  describe "POST /webhooks/twilio/inbound" do
    let(:inbound_sms_params) do
      {
        From: "+15558675309",
        Body: "HELP",
        MessageSid: "twilio-sid-inbound-12345"
      }
    end

    let(:cancel_sms_params) do
      {
        From: "+15558675309",
        Body: "CANCEL",
        MessageSid: "twilio-sid-inbound-67890"
      }
    end

    let(:confirm_sms_params) do
      {
        From: "+15558675309",
        Body: "CONFIRM",
        MessageSid: "twilio-sid-inbound-54321"
      }
    end

    let(:other_sms_params) do
      {
        From: "+15558675309",
        Body: "Hello, I have a question",
        MessageSid: "twilio-sid-inbound-98765"
      }
    end

    it "processes HELP keyword inbound message" do
      expect(Rails.logger).to receive(:info).with(a_string_matching(/Received Twilio inbound SMS/))
      expect(Rails.logger).to receive(:info).with("Inbound SMS from +15558675309: HELP")
      expect(Rails.logger).to receive(:info).with("HELP keyword received from +15558675309")
      allow(Rails.logger).to receive(:info) # Allow other Rails internal logging

      post "/webhooks/twilio/inbound", params: inbound_sms_params

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include("status" => "received")
    end

    it "processes CANCEL keyword inbound message" do
      expect(Rails.logger).to receive(:info).with(a_string_matching(/Received Twilio inbound SMS/))
      expect(Rails.logger).to receive(:info).with("Inbound SMS from +15558675309: CANCEL")
      expect(Rails.logger).to receive(:info).with("CANCEL/STOP keyword received from +15558675309")
      allow(Rails.logger).to receive(:info) # Allow other Rails internal logging

      post "/webhooks/twilio/inbound", params: cancel_sms_params

      expect(response).to have_http_status(:ok)
    end

    it "processes CONFIRM keyword inbound message" do
      expect(Rails.logger).to receive(:info).with(a_string_matching(/Received Twilio inbound SMS/))
      expect(Rails.logger).to receive(:info).with("Inbound SMS from +15558675309: CONFIRM")
      expect(Rails.logger).to receive(:info).with("CONFIRM keyword received from +15558675309")
      allow(Rails.logger).to receive(:info) # Allow other Rails internal logging

      post "/webhooks/twilio/inbound", params: confirm_sms_params

      expect(response).to have_http_status(:ok)
    end

    it "processes other inbound messages" do
      expect(Rails.logger).to receive(:info).with(a_string_matching(/Received Twilio inbound SMS/))
      expect(Rails.logger).to receive(:info).with("Inbound SMS from +15558675309: Hello, I have a question")
      expect(Rails.logger).to receive(:info).with("Other inbound message from +15558675309: Hello, I have a question")
      allow(Rails.logger).to receive(:info) # Allow other Rails internal logging

      post "/webhooks/twilio/inbound", params: other_sms_params

      expect(response).to have_http_status(:ok)
    end

    it "handles STOP keyword like CANCEL" do
      stop_params = cancel_sms_params.merge(Body: "STOP")
      
      expect(Rails.logger).to receive(:info).with(a_string_matching(/Received Twilio inbound SMS/))
      expect(Rails.logger).to receive(:info).with("Inbound SMS from +15558675309: STOP")
      expect(Rails.logger).to receive(:info).with("CANCEL/STOP keyword received from +15558675309")
      allow(Rails.logger).to receive(:info) # Allow other Rails internal logging

      post "/webhooks/twilio/inbound", params: stop_params

      expect(response).to have_http_status(:ok)
    end

    it "is case insensitive for keywords" do
      lowercase_help_params = inbound_sms_params.merge(Body: "help")
      
      expect(Rails.logger).to receive(:info).with(a_string_matching(/Received Twilio inbound SMS/))
      expect(Rails.logger).to receive(:info).with("Inbound SMS from +15558675309: help")
      expect(Rails.logger).to receive(:info).with("HELP keyword received from +15558675309")
      allow(Rails.logger).to receive(:info) # Allow other Rails internal logging

      post "/webhooks/twilio/inbound", params: lowercase_help_params

      expect(response).to have_http_status(:ok)
    end
  end
end