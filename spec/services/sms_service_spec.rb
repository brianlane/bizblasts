# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SmsService, type: :service do
  let!(:tenant) { create(:business) }
  let!(:customer) { create(:tenant_customer, business: tenant, phone: "+15558675309") }
  let(:valid_phone) { customer.phone }
  let(:invalid_phone) { "123" }
  let(:message) { "Test message" }
  
  # Mock Twilio client and response
  let(:twilio_client) { instance_double(Twilio::REST::Client) }
  let(:twilio_messages) { double("Messages") }
  let(:twilio_response) { double("MessageResource", sid: "twilio-sid-123") }
  let(:twilio_response_empty_sid) { double("MessageResource", sid: nil) }

  around do |example|
    ActsAsTenant.with_tenant(tenant) do
      example.run
    end
  end

  before do
    # Mock Twilio client setup
    allow(Twilio::REST::Client).to receive(:new).with(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN).and_return(twilio_client)
    allow(twilio_client).to receive(:messages).and_return(twilio_messages)
  end

  describe '.send_message' do
    context 'with a valid phone number' do
      context 'when Twilio API call succeeds' do
        before do
          allow(twilio_messages).to receive(:create).with(
            messaging_service_sid: TWILIO_MESSAGING_SERVICE_SID,
            to: valid_phone,
            body: message
          ).and_return(twilio_response)
        end

        it 'creates an SmsMessage record with sent status' do
          expect {
            described_class.send_message(valid_phone, message, { tenant_customer_id: customer.id })
          }.to change(SmsMessage, :count).by(1)
          
          sms = SmsMessage.last
          expect(sms.phone_number).to eq(valid_phone)
          expect(sms.content).to eq(message)
          expect(sms.tenant_customer).to eq(customer)
          expect(sms.status).to eq('sent')
          expect(sms.external_id).to eq("twilio-sid-123")
          expect(sms.sent_at).to be_present
        end

        it 'returns success: true with correct data' do
          result = described_class.send_message(valid_phone, message, { tenant_customer_id: customer.id })
          
          expect(result[:success]).to be true
          expect(result[:sms_message]).to be_persisted
          expect(result[:sms_message].status).to eq('sent')
          expect(result[:external_id]).to eq("twilio-sid-123")
        end

        it 'logs successful SMS send' do
          expect(Rails.logger).to receive(:info).with("SMS sent successfully to #{valid_phone} with Twilio SID: twilio-sid-123")
          described_class.send_message(valid_phone, message, { tenant_customer_id: customer.id })
        end

        context 'when Twilio response lacks a message SID' do
          before do
            allow(twilio_messages).to receive(:create).with(
              messaging_service_sid: TWILIO_MESSAGING_SERVICE_SID,
              to: valid_phone,
              body: message
            ).and_return(twilio_response_empty_sid)
          end

          it 'marks the sms as failed and returns an error' do
            result = described_class.send_message(valid_phone, message, { tenant_customer_id: customer.id })

            expect(result[:success]).to be false
            expect(result[:error]).to eq("Unexpected error: Twilio did not return a message SID")

            sms = SmsMessage.last
            expect(sms.status).to eq('failed')
            expect(sms.error_message).to eq("Unexpected error: Twilio did not return a message SID")
          end
        end
      end

      context 'when Twilio API raises RestError' do
        let(:twilio_error) do
          # Create a proper mock of Twilio::REST::RestError
          error_class = Class.new(StandardError)
          error_class.define_method(:initialize) { |msg| super(msg) }
          
          # Make it behave like Twilio::REST::RestError for is_a? checks
          stub_const('Twilio::REST::RestError', error_class)
          
          error_class.new("Invalid destination number")
        end
        
        before do
          allow(twilio_messages).to receive(:create).and_raise(twilio_error)
        end

        it 'creates an SmsMessage record with failed status' do
          expect {
            described_class.send_message(valid_phone, message, { tenant_customer_id: customer.id })
          }.to change(SmsMessage, :count).by(1)
          
          sms = SmsMessage.last
          expect(sms.status).to eq('failed')
          expect(sms.error_message).to eq("Twilio API error: Invalid destination number")
          expect(sms.external_id).to be_nil
          expect(sms.sent_at).to be_nil
        end

        it 'returns success: false with error message' do
          result = described_class.send_message(valid_phone, message, { tenant_customer_id: customer.id })
          
          expect(result[:success]).to be false
          expect(result[:error]).to eq("Twilio API error: Invalid destination number")
          expect(result[:sms_message]).to be_persisted
        end

        it 'logs error' do
          expect(Rails.logger).to receive(:error).with("SMS failed to send to #{valid_phone}: Twilio API error: Invalid destination number")
          described_class.send_message(valid_phone, message, { tenant_customer_id: customer.id })
        end
      end

      context 'when unexpected error occurs' do
        let(:unexpected_error) { StandardError.new("Network timeout") }
        
        before do
          allow(twilio_messages).to receive(:create).and_raise(unexpected_error)
        end

        it 'handles unexpected errors gracefully' do
          result = described_class.send_message(valid_phone, message, { tenant_customer_id: customer.id })
          
          expect(result[:success]).to be false
          expect(result[:error]).to eq("Unexpected error: Network timeout")
          
          sms = SmsMessage.last
          expect(sms.status).to eq('failed')
          expect(sms.error_message).to eq("Unexpected error: Network timeout")
        end
      end
    end

    context 'with an invalid phone number' do
      it 'returns success: false and an error message' do
        result = described_class.send_message(invalid_phone, message)
        expect(result[:success]).to be false
        expect(result[:error]).to eq("Invalid phone number format")
      end

      it 'does not create an SmsMessage record' do
        expect {
          described_class.send_message(invalid_phone, message)
        }.not_to change(SmsMessage, :count)
      end

      it 'does not call Twilio API' do
        expect(twilio_messages).not_to receive(:create)
        described_class.send_message(invalid_phone, message)
      end
    end
  end
  
  describe '.send_booking_confirmation' do
    let!(:service) { create(:service, name: "Consultation", business: tenant) }
    let!(:booking) { create(:booking, tenant_customer: customer, service: service, start_time: Time.current + 3.days, business: tenant) }
    
    it 'calls send_message with the correct arguments and formatted message' do
      expected_message = "Booking confirmed: Consultation on #{booking.local_start_time.strftime('%b %d at %I:%M %p')}. " \
                         "Reply HELP for assistance or CANCEL to cancel your booking."
      expected_options = { 
        tenant_customer_id: customer.id,
        booking_id: booking.id,
        business_id: tenant.id
      }
      
      expect(described_class).to receive(:send_message)
        .with(customer.phone, expected_message, expected_options)
        .and_return({ success: true, sms_message: double("SmsMessage"), external_id: "test-uuid" })
        
      described_class.send_booking_confirmation(booking)
    end
  end

  describe '.send_booking_reminder' do
    let!(:service) { create(:service, name: "Follow-up", business: tenant) }
    let!(:booking) { create(:booking, tenant_customer: customer, service: service, start_time: Time.current + 1.day, business: tenant) }
    
    context 'for 24h timeframe' do
      it 'calls send_message with the correct arguments and formatted message' do
        expected_message = "Reminder: Your Follow-up is tomorrow at #{booking.local_start_time.strftime('%I:%M %p')}. " \
                           "Reply HELP for assistance or CONFIRM to confirm."
        expected_options = { 
          tenant_customer_id: customer.id,
          booking_id: booking.id,
          business_id: tenant.id
        }
        
        expect(described_class).to receive(:send_message)
          .with(customer.phone, expected_message, expected_options)
          .and_return({ success: true, sms_message: double("SmsMessage"), external_id: "test-uuid" })
          
        described_class.send_booking_reminder(booking, '24h')
      end
    end

    context 'for 1h timeframe' do
       it 'calls send_message with the correct arguments and formatted message' do
         expected_message = "Reminder: Your Follow-up is in 1 hour at #{booking.local_start_time.strftime('%I:%M %p')}. " \
                            "Reply HELP for assistance or CONFIRM to confirm."
         expected_options = { 
           tenant_customer_id: customer.id,
           booking_id: booking.id,
           business_id: tenant.id
         }
         
         expect(described_class).to receive(:send_message)
           .with(customer.phone, expected_message, expected_options)
           .and_return({ success: true, sms_message: double("SmsMessage"), external_id: "test-uuid" })
           
         described_class.send_booking_reminder(booking, '1h')
       end
    end
  end
  
  describe '.process_webhook' do
    let!(:campaign_for_webhook) { create(:marketing_campaign, name: "Webhook Test Campaign", business: tenant) }
    let!(:sent_sms) { create(:sms_message, :sent, external_id: "twilio-sid-delivered", marketing_campaign: campaign_for_webhook, tenant_customer: customer) }
    let!(:failed_sms) { create(:sms_message, :sent, external_id: "twilio-sid-failed", marketing_campaign: campaign_for_webhook, tenant_customer: customer) }
    
    # Twilio webhook format - using both symbol and string keys to test both
    let(:delivered_params) { { MessageSid: "twilio-sid-delivered", MessageStatus: "delivered" } }
    let(:failed_params) { { "MessageSid" => "twilio-sid-failed", "MessageStatus" => "failed", "ErrorCode" => "21211" } }
    let(:undelivered_params) { { MessageSid: "twilio-sid-failed", MessageStatus: "undelivered" } }
    let(:sent_params) { { MessageSid: "twilio-sid-delivered", MessageStatus: "sent" } }
    let(:queued_params) { { MessageSid: "twilio-sid-delivered", MessageStatus: "queued" } }
    let(:accepted_params) { { MessageSid: "twilio-sid-delivered", MessageStatus: "accepted" } }
    let(:unknown_params) { { MessageSid: "twilio-sid-delivered", MessageStatus: "unknown_status" } }
    let(:not_found_params) { { MessageSid: "twilio-sid-notfound", MessageStatus: "delivered" } }
    let(:missing_sid_params) { { MessageStatus: "delivered" } }
    let(:missing_status_params) { { MessageSid: "twilio-sid-delivered" } }

    context 'with delivered status' do
      it 'updates the sms message status to delivered' do
        result = described_class.process_webhook(delivered_params)
        expect(result[:success]).to be true
        expect(result[:status]).to eq("delivered")
        expect(sent_sms.reload.status).to eq('delivered')
        expect(sent_sms.delivered_at).to be_present
      end
    end

    context 'with failed status' do
      it 'updates the sms message status to failed and records error with code' do
        result = described_class.process_webhook(failed_params)
        expect(result[:success]).to be false
        expect(failed_sms.reload.status).to eq('failed')
        expect(failed_sms.error_message).to eq("Delivery failed (Code: 21211)")
        expect(result[:error]).to eq("Delivery failed (Code: 21211)")
      end
    end

    context 'with undelivered status' do
      it 'updates the sms message status to failed' do
        result = described_class.process_webhook(undelivered_params)
        expect(result[:success]).to be false
        expect(failed_sms.reload.status).to eq('failed')
        expect(failed_sms.error_message).to eq("Delivery failed")
      end
    end

    context 'with sent status' do
      it 'acknowledges but does not change status' do
        original_status = sent_sms.status
        result = described_class.process_webhook(sent_params)
        expect(result[:success]).to be true
        expect(result[:status]).to eq("acknowledged")
        expect(sent_sms.reload.status).to eq(original_status)
      end
    end

    context 'with queued status' do
      it 'acknowledges but does not change status' do
        original_status = sent_sms.status
        result = described_class.process_webhook(queued_params)
        expect(result[:success]).to be true
        expect(result[:status]).to eq("acknowledged")
        expect(sent_sms.reload.status).to eq(original_status)
      end
    end

    context 'with accepted status' do
      it 'acknowledges but does not change status' do
        original_status = sent_sms.status
        result = described_class.process_webhook(accepted_params)
        expect(result[:success]).to be true
        expect(result[:status]).to eq("acknowledged")
        expect(sent_sms.reload.status).to eq(original_status)
      end
    end

    context 'with unknown status' do
      it 'returns success true but logs warning' do
        expect(Rails.logger).to receive(:warn).with("Unknown Twilio status received: unknown_status")
        result = described_class.process_webhook(unknown_params)
        expect(result[:success]).to be true
        expect(result[:status]).to eq("unknown")
        expect(sent_sms.reload.status).to eq('sent')
      end
    end

    context 'when MessageSid is not found' do
      it 'returns success false and an error' do
        result = described_class.process_webhook(not_found_params)
        expect(result[:success]).to be false
        expect(result[:error]).to eq("Message not found for SID: twilio-sid-notfound")
      end
    end

    context 'when MessageSid is missing' do
      it 'returns success false and an error' do
        result = described_class.process_webhook(missing_sid_params)
        expect(result[:success]).to be false
        expect(result[:error]).to eq("Missing MessageSid in webhook")
      end
    end

    context 'when MessageStatus is missing' do
      it 'returns success false and an error' do
        result = described_class.process_webhook(missing_status_params)
        expect(result[:success]).to be false
        expect(result[:error]).to eq("Missing MessageStatus in webhook")
      end
    end

    it 'logs webhook processing' do
      expect(Rails.logger).to receive(:info).with("Processing Twilio webhook for message twilio-sid-delivered with status: delivered")
      described_class.process_webhook(delivered_params)
    end
  end
end 