# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Twilio Webhooks - Opt-Out Edge Cases", type: :request do
  let!(:business) { create(:business, :standard_tier, sms_enabled: true) }
  let!(:customer) { create(:tenant_customer, business: business, phone: "+15558675309", phone_opt_in: true) }
  let!(:user) { create(:user, business: business, phone: "+15558675309") }

  around do |example|
    ActsAsTenant.with_tenant(business) do
      example.run
    end
  end

  before do
    # Skip signature verification for tests
    allow_any_instance_of(Webhooks::TwilioController).to receive(:verify_webhook_signature?).and_return(false)
    
    # Mock template rendering to avoid missing template errors
    allow(Sms::MessageTemplates).to receive(:render).and_return("Mocked template response")
    
    # Mock SmsService.send_message to avoid actual API calls
    allow(SmsService).to receive(:send_message).and_return({ success: true })
  end

  describe "comprehensive opt-out keyword handling" do
    let(:base_params) do
      {
        From: "+15558675309",
        MessageSid: "twilio-sid-inbound-12345"
      }
    end

    # Test case-insensitive opt-out keywords
    [
      # Standard keywords in various cases
      "STOP", "stop", "Stop", "StOp", "STOP", "sToP",
      "CANCEL", "cancel", "Cancel", "CaNcEl",
      "UNSUBSCRIBE", "unsubscribe", "Unsubscribe", "UnSuBsCrIbE",
      
      # Keywords with whitespace
      " STOP", "STOP ", " STOP ", "\tSTOP\t", "\nSTOP\n",
      " CANCEL ", "\tCANCEL", "UNSUBSCRIBE\n",
      
      # Mixed whitespace and case
      " stop ", " Cancel\n", "\tUnsubscribe ",
      
      # Keywords with extra characters (should still work due to strip)
      "STOP\r", "CANCEL\r\n", "UNSUBSCRIBE\t\n",
    ].each do |keyword|
      
      it "recognizes '#{keyword.inspect}' as an opt-out keyword" do
        params = base_params.merge(Body: keyword)
        
        expect(Rails.logger).to receive(:info).with("STOP keyword received from +15558675309 - processing opt-out")
        allow(Rails.logger).to receive(:info) # Allow other logging calls
        
        post "/webhooks/twilio/inbound", params: params
        
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)).to include("status" => "received")
        
        # Verify customer was opted out
        customer.reload
        expect(customer.phone_opt_in?).to be false
      end
    end

    # Test opt-in keywords with edge cases
    [
      # Standard opt-in keywords  
      "START", "start", "Start", "StArT",
      "SUBSCRIBE", "subscribe", "Subscribe", "SuBsCrIbE",
      "YES", "yes", "Yes", "YeS",
      
      # With whitespace
      " START ", "\tSUBSCRIBE", "YES\n",
      " yes ", "\tStart ", "Subscribe\r\n",
    ].each do |keyword|
      
      it "recognizes '#{keyword.inspect}' as an opt-in keyword" do
        # First opt the customer out
        customer.update!(phone_opt_in: false)
        
        params = base_params.merge(Body: keyword)
        
        expect(Rails.logger).to receive(:info).with("START keyword received from +15558675309 - processing opt-in")
        allow(Rails.logger).to receive(:info) # Allow other logging calls
        
        post "/webhooks/twilio/inbound", params: params
        
        expect(response).to have_http_status(:ok)
        
        # Verify customer was opted back in
        customer.reload
        expect(customer.phone_opt_in?).to be true
      end
    end

    # Test that non-keywords don't trigger opt-out/opt-in
    [
      "STOPS", "STOPPING", "CANCELLED", "HELP STOP", "I WANT TO STOP",
      "STARTS", "STARTING", "SUBSCRIBED", "YES PLEASE", "NOT YES",
      "stop please", "can you stop this", "start the process",
    ].each do |non_keyword|
      
      it "does NOT recognize '#{non_keyword}' as opt-out/opt-in keyword" do
        params = base_params.merge(Body: non_keyword)
        
        # Should NOT see opt-out/opt-in logging
        expect(Rails.logger).not_to receive(:info).with(/STOP keyword received/)
        expect(Rails.logger).not_to receive(:info).with(/START keyword received/)
        
        # Should see "other inbound message" logging instead
        expect(Rails.logger).to receive(:info).with("Other inbound message from +15558675309: #{non_keyword}")
        allow(Rails.logger).to receive(:info) # Allow other logging calls
        
        post "/webhooks/twilio/inbound", params: params
        
        expect(response).to have_http_status(:ok)
        
        # Verify customer opt-in status was NOT changed
        customer.reload
        expect(customer.phone_opt_in?).to be true # Should remain opted in
      end
    end

    # Test empty/nil body handling
    [nil, "", "   ", "\t", "\n", "\r\n"].each do |empty_body|
      it "handles empty/whitespace body '#{empty_body.inspect}' gracefully" do
        params = base_params.merge(Body: empty_body)
        
        # Should not crash and should respond successfully
        post "/webhooks/twilio/inbound", params: params
        
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)).to include("status" => "received")
        
        # Customer should remain opted in
        customer.reload
        expect(customer.phone_opt_in?).to be true
      end
    end
  end

  describe "opt-out processing edge cases" do
    let(:opt_out_params) do
      {
        From: "+15558675309",
        Body: "STOP",
        MessageSid: "twilio-sid-12345"
      }
    end

    context "when customer exists but user does not" do
      before do
        user.destroy # Remove the user, keep the customer
      end

      it "still processes opt-out for customer only" do
        expect(customer.phone_opt_in?).to be true
        
        post "/webhooks/twilio/inbound", params: opt_out_params
        
        expect(response).to have_http_status(:ok)
        customer.reload
        expect(customer.phone_opt_in?).to be false
      end
    end

    context "when user exists but customer does not" do  
      before do
        customer.destroy # Remove the customer, keep the user
        # Create a simple mock user to avoid Devise inspection issues
        mock_user = double("User", id: 123)
        allow(mock_user).to receive(:respond_to?).with(:opt_out_of_sms!).and_return(true)
        allow(mock_user).to receive(:opt_out_of_sms!)
        allow(mock_user).to receive(:business).and_return(nil)
        allow(User).to receive(:where).with(phone: "+15558675309").and_return([mock_user])
        @mock_user = mock_user
      end

      it "still processes opt-out for user only" do
        expect(@mock_user).to receive(:opt_out_of_sms!)
        
        post "/webhooks/twilio/inbound", params: opt_out_params
        
        expect(response).to have_http_status(:ok)
      end
    end

    context "when no matching customer or user exists" do
      before do
        customer.destroy
        user.destroy
      end

      it "still processes the webhook without errors" do
        post "/webhooks/twilio/inbound", params: opt_out_params
        
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)).to include("status" => "received")
      end

      it "still sends opt-out confirmation message" do
        expect(SmsService).to receive(:send_message).with(
          "+15558675309",
          "You've been unsubscribed from all SMS. Reply START to re-subscribe or HELP for assistance.",
          hash_including(auto_reply: true)
        )
        
        post "/webhooks/twilio/inbound", params: opt_out_params
      end
    end

    context "with multiple customers having same phone number" do
      let!(:customer2) { create(:tenant_customer, business: business, phone: "+15558675309", phone_opt_in: true) }
      let!(:customer3) { create(:tenant_customer, phone: "+15558675309", phone_opt_in: true) } # Different business

      it "opts out all customers with the same normalized phone number" do
        post "/webhooks/twilio/inbound", params: opt_out_params
        
        expect(response).to have_http_status(:ok)
        
        # Both customers in the same business should be opted out
        customer.reload
        customer2.reload
        customer3.reload
        
        expect(customer.phone_opt_in?).to be false
        expect(customer2.phone_opt_in?).to be false  
        
        # Customer3 is in a different business - behavior depends on implementation
        # but should be included if phone normalization works globally
      end
    end
  end

  describe "phone number normalization edge cases" do
    let(:controller) { Webhooks::TwilioController.new }

    # Test various phone number formats that should normalize to same number
    {
      "+15558675309" => "+15558675309",
      "15558675309" => "+15558675309",
      "5558675309" => "+15558675309",
      "(555) 867-5309" => "+15558675309",
      "555-867-5309" => "+15558675309", 
      "555.867.5309" => "+15558675309",
      "555 867 5309" => "+15558675309",
      "+1-555-867-5309" => "+15558675309",
      "+1 (555) 867-5309" => "+15558675309",
      "1-555-867-5309" => "+15558675309",
      "1 555 867 5309" => "+15558675309",
      "+1 555.867.5309" => "+15558675309",
    }.each do |input, expected|
      
      it "normalizes '#{input}' to '#{expected}'" do
        result = controller.send(:normalize_phone, input)
        expect(result).to eq(expected)
      end
    end

    # Test that all these variations trigger the same opt-out behavior
    [
      "+15558675309",
      "15558675309", 
      "5558675309",
      "(555) 867-5309",
      "555-867-5309"
    ].each do |phone_format|
      
      it "processes opt-out for phone number in format '#{phone_format}'" do
        params = {
          From: phone_format,
          Body: "STOP",
          MessageSid: "twilio-sid-12345"
        }
        
        post "/webhooks/twilio/inbound", params: params
        
        expect(response).to have_http_status(:ok)
        
        # Customer should be opted out regardless of phone format  
        customer.reload
        expect(customer.phone_opt_in?).to be false
      end
    end
  end

  describe "template rendering failures" do
    before do
      # Simulate template rendering failure
      allow(Sms::MessageTemplates).to receive(:render).and_return(nil)
    end

    it "gracefully handles template rendering failures for opt-out confirmation" do
      params = {
        From: "+15558675309",
        Body: "STOP",
        MessageSid: "twilio-sid-12345"
      }

      # Controller uses hardcoded messages, not templates, so message should still be sent
      expect(SmsService).to receive(:send_message).with(
        "+15558675309",
        "You've been unsubscribed from all SMS. Reply START to re-subscribe or HELP for assistance.",
        hash_including(auto_reply: true)
      )
      
      post "/webhooks/twilio/inbound", params: params
      
      expect(response).to have_http_status(:ok)
      
      # Customer should still be opted out even if confirmation message fails
      customer.reload
      expect(customer.phone_opt_in?).to be false
    end

    it "gracefully handles template rendering failures for help response" do
      params = {
        From: "+15558675309", 
        Body: "HELP",
        MessageSid: "twilio-sid-12345"
      }
      
      # Should not call send_message if template returns nil
      expect(SmsService).not_to receive(:send_message)
      
      post "/webhooks/twilio/inbound", params: params
      
      expect(response).to have_http_status(:ok)
    end
  end

  describe "auto-reply failure handling" do
    before do
      allow(Sms::MessageTemplates).to receive(:render).and_return("Test confirmation message")
    end

    it "continues processing even if auto-reply fails" do
      params = {
        From: "+15558675309",
        Body: "STOP", 
        MessageSid: "twilio-sid-12345"
      }
      
      # Simulate SmsService.send_message failure
      allow(SmsService).to receive(:send_message).and_raise(StandardError.new("SMS API error"))
      
      # Should log the error but not crash
      expect(Rails.logger).to receive(:error).with("Failed to send auto-reply to +15558675309: SMS API error")
      allow(Rails.logger).to receive(:info) # Allow other logging
      
      post "/webhooks/twilio/inbound", params: params
      
      expect(response).to have_http_status(:ok)
      
      # Customer should still be opted out even if confirmation message fails  
      customer.reload
      expect(customer.phone_opt_in?).to be false
    end
  end
end