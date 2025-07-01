# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SmsService, type: :service do
  let!(:tenant) { create(:business) }
  let!(:customer) { create(:tenant_customer, business: tenant, phone: "+15558675309") }
  let(:valid_phone) { customer.phone }
  let(:invalid_phone) { "123" }
  let(:message) { "Test message" }

  around do |example|
    ActsAsTenant.with_tenant(tenant) do
      example.run
    end
  end

  describe '.send_message' do
    context 'with a valid phone number' do
      it 'creates an SmsMessage record' do
        expect {
          described_class.send_message(valid_phone, message, { tenant_customer_id: customer.id, business_id: tenant.id })
        }.to change(SmsMessage, :count).by(1)
        
        sms = SmsMessage.last
        expect(sms.phone_number).to eq(valid_phone)
        expect(sms.content).to eq(message)
        expect(sms.tenant_customer).to eq(customer)
        expect(sms.status).to match(/sent|failed/) # Depending on simulated success
      end

      # The service uses rand > 0.1 to simulate success/failure
      # We can test both outcomes by stubbing SecureRandom or rand, 
      # or just test the record creation and basic return structure.
      # Let's test the structure and status update.

      context 'when simulated send succeeds' do
        before do
          # Ensure rand > 0.1 is true
          allow(described_class).to receive(:rand).and_return(0.5)
        end

        it 'returns success: true and updates record to sent' do
          result = described_class.send_message(valid_phone, message, { tenant_customer_id: customer.id, business_id: tenant.id })
          expect(result[:success]).to be true
          expect(result[:sms_message]).to be_persisted
          expect(result[:sms_message].status).to eq('sent')
          expect(result[:external_id]).to be_present
        end
      end

      context 'when simulated send fails' do
         before do
           # Ensure rand > 0.1 is false
           allow(described_class).to receive(:rand).and_return(0.05)
         end

         it 'returns success: false and updates record to failed' do
           result = described_class.send_message(valid_phone, message, { tenant_customer_id: customer.id, business_id: tenant.id })
           expect(result[:success]).to be false
           expect(result[:sms_message]).to be_persisted
           expect(result[:sms_message].status).to eq('failed')
           expect(result[:error]).to include("simulated failure")
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
        .and_call_original # Allow original method to run for return value/side effects if needed
        
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
          .and_call_original
          
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
           .and_call_original
           
         described_class.send_booking_reminder(booking, '1h')
       end
    end
  end
  
  describe '.process_webhook' do
    # Create one campaign for both messages
    let!(:campaign_for_webhook) { create(:marketing_campaign, name: "Webhook Test Campaign", business: tenant) }
    let!(:sent_sms) { create(:sms_message, :sent, external_id: "SM_SENT123", marketing_campaign: campaign_for_webhook, tenant_customer: customer) }
    let!(:failed_sms) { create(:sms_message, :sent, external_id: "SM_FAILED456", marketing_campaign: campaign_for_webhook, tenant_customer: customer) }
    let(:delivered_params) { { message_id: "SM_SENT123", status: "delivered" } }
    let(:failed_params) { { message_id: "SM_FAILED456", status: "failed", error_message: "Carrier error" } }
    let(:unknown_params) { { message_id: "SM_SENT123", status: "unknown" } }
    let(:not_found_params) { { message_id: "SM_NOTFOUND", status: "delivered" } }

    context 'with delivered status' do
      it 'updates the sms message status to delivered' do
        result = described_class.process_webhook(delivered_params)
        expect(result[:success]).to be true
        expect(sent_sms.reload.status).to eq('delivered')
        expect(sent_sms.delivered_at).to be_present
      end
    end

    context 'with failed status' do
      it 'updates the sms message status to failed and records error' do
        result = described_class.process_webhook(failed_params)
        expect(result[:success]).to be false
        expect(failed_sms.reload.status).to eq('failed')
        expect(failed_sms.error_message).to eq("Carrier error")
        expect(result[:error]).to eq("Carrier error")
      end
    end

    context 'with unknown status' do
      it 'returns success true but does not change sms status' do
        result = described_class.process_webhook(unknown_params)
        expect(result[:success]).to be true
        expect(result[:status]).to eq("unknown")
        expect(sent_sms.reload.status).to eq('sent') # Still sent
      end
    end

    context 'when message_id is not found' do
      it 'returns success false and an error' do
        result = described_class.process_webhook(not_found_params)
        expect(result[:success]).to be false
        expect(result[:error]).to eq("Message not found")
      end
    end
  end
end 