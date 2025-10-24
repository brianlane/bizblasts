require 'rails_helper'

RSpec.describe Webhooks::TwilioController, 'Business-specific opt-out', type: :controller do
  let(:business1) { create(:business, sms_enabled: true, tier: 'premium') }
  let(:business2) { create(:business, sms_enabled: true, tier: 'premium') }
  let(:customer1) { create(:tenant_customer, business: business1, phone: '+15551234567', phone_opt_in: true) }
  let(:customer2) { create(:tenant_customer, business: business2, phone: '+15551234567', phone_opt_in: true) }

  before do
    # Mock Twilio signature verification
    allow(controller).to receive(:verify_webhook_signature?).and_return(false)
  end

  describe 'business-specific opt-out' do
    context 'when business context can be determined' do
      before do
        # Create recent SMS message to establish business context
        SmsMessage.create!(
          phone_number: '+15551234567',
          business: business1,
          tenant_customer: customer1,
          content: 'Test message',
          status: 'sent',
          sent_at: 1.hour.ago
        )
      end

      it 'opts out from specific business only' do
        post :inbound_message, params: {
          From: '+15551234567',
          Body: 'STOP'
        }

        customer1.reload
        customer2.reload

        expect(customer1.opted_out_from_business?(business1)).to be_truthy
        expect(customer2.opted_out_from_business?(business2)).to be_falsey
        expect(customer1.phone_opt_in).to be_truthy # Global opt-in remains
      end

      it 'sends business-specific confirmation message' do
        expect(controller).to receive(:send_auto_reply).with(
          '+15551234567',
          "You've been unsubscribed from #{business1.name} SMS. Reply START to re-subscribe or HELP for assistance."
        )

        post :inbound_message, params: {
          From: '+15551234567',
          Body: 'STOP'
        }
      end
    end

    context 'when no business context found' do
      before do
        # Ensure no recent SMS messages exist that could establish business context
        SmsMessage.for_phone('+15551234567').destroy_all
        # Also ensure no customer records exist for this phone to test true "no context" scenario
        TenantCustomer.where(phone: '+15551234567').destroy_all
      end

      it 'performs business-specific opt-out for most recent customer relationship' do
        # Use a completely new phone number to test multi-business scenario
        test_phone = '+15559999999'

        # Create customers with this phone across different businesses
        # global_customer2 will be more recent (created after global_customer1)
        global_customer1 = create(:tenant_customer, business: business1, phone: test_phone, phone_opt_in: true)
        sleep(0.01) # Ensure different timestamps
        global_customer2 = create(:tenant_customer, business: business2, phone: test_phone, phone_opt_in: true)

        # Expect business-specific opt-out for the most recent customer (business2)
        allow(Rails.logger).to receive(:info).and_call_original
        expect(Rails.logger).to receive(:info).with("STOP keyword received from #{test_phone} - processing opt-out")
        expect(Rails.logger).to receive(:info).with(match(/\[BUSINESS_CONTEXT\] Multiple businesses found for #{Regexp.escape(test_phone)}: .*using most recent customer relationship/))
        expect(Rails.logger).to receive(:info).with("Processing business-specific opt-out for #{test_phone} from business #{business2.id}")
        expect(Rails.logger).to receive(:info).with("Opted out customer #{global_customer2.id} from business #{business2.id}")

        post :inbound_message, params: {
          From: test_phone,
          Body: 'STOP'
        }

        global_customer1.reload
        global_customer2.reload

        # Customer 1 should remain globally opted in (not affected)
        expect(global_customer1.phone_opt_in).to be_truthy
        expect(global_customer1.opted_out_from_business?(business1)).to be_falsey

        # Customer 2 should be opted out from business2 specifically, but remain globally opted in
        expect(global_customer2.phone_opt_in).to be_truthy
        expect(global_customer2.opted_out_from_business?(business2)).to be_truthy
      end

      it 'performs global opt-out when no customer records exist' do
        # Use a phone number with no customer records anywhere
        unknown_phone = '+15556666666'

        # This should trigger global opt-out since no business context can be determined
        allow(Rails.logger).to receive(:info).and_call_original
        expect(Rails.logger).to receive(:info).with("STOP keyword received from #{unknown_phone} - processing opt-out")
        expect(Rails.logger).to receive(:info).with("Processing global opt-out for #{unknown_phone} (no business context found)")

        post :inbound_message, params: {
          From: unknown_phone,
          Body: 'STOP'
        }

        expect(response).to have_http_status(:ok)
      end

      it 'sends global opt-out confirmation' do
        expect(controller).to receive(:send_auto_reply).with(
          '+15551234567',
          "You've been unsubscribed from all SMS. Reply START to re-subscribe or HELP for assistance."
        )

        post :inbound_message, params: {
          From: '+15551234567',
          Body: 'STOP'
        }
      end
    end
  end

  describe 'business-specific opt-in' do
    before do
      # Opt out from business1 specifically
      customer1.opt_out_from_business!(business1)

      # Create recent SMS message to establish business context
      SmsMessage.create!(
        phone_number: '+15551234567',
        business: business1,
        tenant_customer: customer1,
        content: 'Test message',
        status: 'sent',
        sent_at: 1.hour.ago
      )
    end

    it 'records invitation response' do
      # Create a pending invitation
      invitation = SmsOptInInvitation.create!(
        phone_number: '+15551234567',
        business: business1,
        context: 'booking_confirmation',
        sent_at: 1.day.ago
      )

      post :inbound_message, params: {
        From: '+15551234567',
        Body: 'YES'
      }

      invitation.reload
      expect(invitation.response).to eq('YES')
      expect(invitation.responded_at).to be_within(1.second).of(Time.current)
      expect(invitation.successful_opt_in).to be_truthy
    end

    it 'opts in to specific business' do
      post :inbound_message, params: {
        From: '+15551234567',
        Body: 'YES'
      }

      customer1.reload
      expect(customer1.opted_out_from_business?(business1)).to be_falsey
      expect(customer1.phone_opt_in).to be_truthy
    end

    it 'sends business-specific confirmation' do
      expect(controller).to receive(:send_auto_reply).with(
        '+15551234567',
        "You're now subscribed to #{business1.name} SMS notifications. Reply STOP to unsubscribe or HELP for assistance."
      )

      post :inbound_message, params: {
        From: '+15551234567',
        Body: 'YES'
      }
    end
  end

  describe '#determine_business_context' do
    it 'returns business from recent SMS' do
      SmsMessage.create!(
        phone_number: '+15551234567',
        business: business1,
        tenant_customer: customer1,
        content: 'Test message',
        status: 'sent',
        sent_at: 1.hour.ago
      )

      # Create older message from different business
      SmsMessage.create!(
        phone_number: '+15551234567',
        business: business2,
        tenant_customer: customer2,
        content: 'Older message',
        status: 'sent',
        sent_at: 25.hours.ago
      )

      context = controller.send(:determine_business_context, '+15551234567')
      expect(context).to eq(business1)
    end

    it 'returns nil when no recent SMS found' do
      context = controller.send(:determine_business_context, '+15551234567')
      expect(context).to be_nil
    end

    it 'returns nil when only old SMS found' do
      # Create a customer and SMS message, then delete the customer to test old SMS only
      old_customer = create(:tenant_customer, business: business1, phone: '+15557777777', phone_opt_in: true)
      SmsMessage.create!(
        phone_number: '+15557777777',
        business: business1,
        tenant_customer: old_customer,
        content: 'Old message',
        status: 'sent',
        sent_at: 25.hours.ago
      )

      # Delete the customer to ensure no business context through customer records
      old_customer.destroy

      context = controller.send(:determine_business_context, '+15557777777', conservative: true)
      expect(context).to be_nil
    end
  end

  describe '#record_invitation_response' do
    it 'records response for all recent invitations' do
      invitation1 = SmsOptInInvitation.create!(
        phone_number: '+15551234567',
        business: business1,
        context: 'booking_confirmation',
        sent_at: 1.day.ago
      )

      invitation2 = SmsOptInInvitation.create!(
        phone_number: '+15551234567',
        business: business2,
        context: 'booking_reminder',
        sent_at: 2.days.ago
      )

      controller.send(:record_invitation_response, '+15551234567', 'YES')

      invitation1.reload
      invitation2.reload

      expect(invitation1.response).to eq('YES')
      expect(invitation2.response).to eq('YES')
      expect(invitation1.successful_opt_in).to be_truthy
      expect(invitation2.successful_opt_in).to be_truthy
    end

    it 'does not record response for old invitations' do
      old_invitation = SmsOptInInvitation.create!(
        phone_number: '+15551234567',
        business: business1,
        context: 'booking_confirmation',
        sent_at: 31.days.ago
      )

      controller.send(:record_invitation_response, '+15551234567', 'YES')

      old_invitation.reload
      expect(old_invitation.response).to be_nil
    end

    it 'does not record response for already responded invitations' do
      invitation = SmsOptInInvitation.create!(
        phone_number: '+15551234567',
        business: business1,
        context: 'booking_confirmation',
        sent_at: 1.day.ago,
        responded_at: 12.hours.ago,
        response: 'STOP'
      )

      controller.send(:record_invitation_response, '+15551234567', 'YES')

      invitation.reload
      expect(invitation.response).to eq('STOP') # Should not change
    end
  end
end
