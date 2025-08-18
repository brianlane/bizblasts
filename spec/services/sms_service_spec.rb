# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SmsService, type: :service do
  let!(:tenant) { create(:business) }
  let!(:customer) { create(:tenant_customer, business: tenant, phone: "+15558675309") }
  let(:valid_phone) { customer.phone }
  let(:invalid_phone) { "123" }
  let(:message) { "Test message" }
  
  # Mock Plivo client and response
  let(:plivo_client) { instance_double(Plivo::RestClient) }
  let(:plivo_messages) { double("Messages") }
  let(:plivo_response) { double("Response", message_uuid: ["plivo-uuid-123"]) }

  around do |example|
    ActsAsTenant.with_tenant(tenant) do
      example.run
    end
  end

  before do
    # Mock Plivo client setup
    allow(Plivo::RestClient).to receive(:new).with(PLIVO_AUTH_ID, PLIVO_AUTH_TOKEN).and_return(plivo_client)
    allow(plivo_client).to receive(:messages).and_return(plivo_messages)
  end

  describe '.send_message' do
    context 'with a valid phone number' do
      context 'when Plivo API call succeeds' do
        before do
          allow(plivo_messages).to receive(:create).with(
            src: PLIVO_SOURCE_NUMBER,
            dst: valid_phone,
            text: message
          ).and_return(plivo_response)
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
          expect(sms.external_id).to eq("plivo-uuid-123")
          expect(sms.sent_at).to be_present
        end

        it 'returns success: true with correct data' do
          result = described_class.send_message(valid_phone, message, { tenant_customer_id: customer.id })
          
          expect(result[:success]).to be true
          expect(result[:sms_message]).to be_persisted
          expect(result[:sms_message].status).to eq('sent')
          expect(result[:external_id]).to eq("plivo-uuid-123")
        end

        it 'logs successful SMS send' do
          expect(Rails.logger).to receive(:info).with("SMS sent successfully to #{valid_phone} with Plivo UUID: plivo-uuid-123")
          described_class.send_message(valid_phone, message, { tenant_customer_id: customer.id })
        end
      end

      context 'when Plivo API raises PlivoRESTError' do
        let(:plivo_error) { Plivo::Exceptions::PlivoRESTError.new("Invalid destination number") }
        
        before do
          allow(plivo_messages).to receive(:create).and_raise(plivo_error)
        end

        it 'creates an SmsMessage record with failed status' do
          expect {
            described_class.send_message(valid_phone, message, { tenant_customer_id: customer.id })
          }.to change(SmsMessage, :count).by(1)
          
          sms = SmsMessage.last
          expect(sms.status).to eq('failed')
          expect(sms.error_message).to eq("Plivo API error: Invalid destination number")
          expect(sms.external_id).to be_nil
          expect(sms.sent_at).to be_nil
        end

        it 'returns success: false with error message' do
          result = described_class.send_message(valid_phone, message, { tenant_customer_id: customer.id })
          
          expect(result[:success]).to be false
          expect(result[:error]).to eq("Plivo API error: Invalid destination number")
          expect(result[:sms_message]).to be_persisted
        end

        it 'logs error' do
          expect(Rails.logger).to receive(:error).with("SMS failed to send to #{valid_phone}: Plivo API error: Invalid destination number")
          described_class.send_message(valid_phone, message, { tenant_customer_id: customer.id })
        end
      end

      context 'when unexpected error occurs' do
        let(:unexpected_error) { StandardError.new("Network timeout") }
        
        before do
          allow(plivo_messages).to receive(:create).and_raise(unexpected_error)
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

      it 'does not call Plivo API' do
        expect(plivo_messages).not_to receive(:create)
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
    let!(:sent_sms) { create(:sms_message, :sent, external_id: "plivo-uuid-delivered", marketing_campaign: campaign_for_webhook, tenant_customer: customer) }
    let!(:failed_sms) { create(:sms_message, :sent, external_id: "plivo-uuid-failed", marketing_campaign: campaign_for_webhook, tenant_customer: customer) }
    
    # Plivo webhook format - using both symbol and string keys to test both
    let(:delivered_params) { { MessageUUID: "plivo-uuid-delivered", Status: "delivered" } }
    let(:failed_params) { { "MessageUUID" => "plivo-uuid-failed", "Status" => "failed", "ErrorCode" => "21211" } }
    let(:undelivered_params) { { MessageUUID: "plivo-uuid-failed", Status: "undelivered" } }
    let(:sent_params) { { MessageUUID: "plivo-uuid-delivered", Status: "sent" } }
    let(:queued_params) { { MessageUUID: "plivo-uuid-delivered", Status: "queued" } }
    let(:unknown_params) { { MessageUUID: "plivo-uuid-delivered", Status: "unknown_status" } }
    let(:not_found_params) { { MessageUUID: "plivo-uuid-notfound", Status: "delivered" } }
    let(:missing_uuid_params) { { Status: "delivered" } }
    let(:missing_status_params) { { MessageUUID: "plivo-uuid-delivered" } }

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

    context 'with unknown status' do
      it 'returns success true but logs warning' do
        expect(Rails.logger).to receive(:warn).with("Unknown Plivo status received: unknown_status")
        result = described_class.process_webhook(unknown_params)
        expect(result[:success]).to be true
        expect(result[:status]).to eq("unknown")
        expect(sent_sms.reload.status).to eq('sent')
      end
    end

    context 'when MessageUUID is not found' do
      it 'returns success false and an error' do
        result = described_class.process_webhook(not_found_params)
        expect(result[:success]).to be false
        expect(result[:error]).to eq("Message not found for UUID: plivo-uuid-notfound")
      end
    end

    context 'when MessageUUID is missing' do
      it 'returns success false and an error' do
        result = described_class.process_webhook(missing_uuid_params)
        expect(result[:success]).to be false
        expect(result[:error]).to eq("Missing MessageUUID in webhook")
      end
    end

    context 'when Status is missing' do
      it 'returns success false and an error' do
        result = described_class.process_webhook(missing_status_params)
        expect(result[:success]).to be false
        expect(result[:error]).to eq("Missing Status in webhook")
      end
    end

    it 'logs webhook processing' do
      expect(Rails.logger).to receive(:info).with("Processing Plivo webhook for message plivo-uuid-delivered with status: delivered")
      described_class.process_webhook(delivered_params)
    end
  end
end 