require 'rails_helper'

RSpec.describe SmsService, 'Invitation Logic', type: :service do
  let(:business) { create(:business, sms_enabled: true, sms_auto_invitations_enabled: true) }
  let(:customer) { create(:tenant_customer, business: business, phone: '+15551234567', phone_opt_in: false) }
  let(:booking) { create(:booking, business: business, tenant_customer: customer) }

  before do
    allow(Rails.application.config).to receive(:sms_enabled).and_return(true)
  end

  describe '.should_send_invitation?' do
    it 'returns true when all conditions are met' do
      expect(SmsService.should_send_invitation?(customer, business, :booking_confirmation)).to be_truthy
    end

    it 'returns false when SMS globally disabled' do
      allow(Rails.application.config).to receive(:sms_enabled).and_return(false)
      expect(SmsService.should_send_invitation?(customer, business, :booking_confirmation)).to be_falsey
    end

    it 'returns false when business auto-invitations disabled' do
      business.update!(sms_auto_invitations_enabled: false)
      expect(SmsService.should_send_invitation?(customer, business, :booking_confirmation)).to be_falsey
    end

    it 'returns false when customer has no phone' do
      customer.update!(phone: nil)
      expect(SmsService.should_send_invitation?(customer, business, :booking_confirmation)).to be_falsey
    end

    it 'returns false when business cannot send SMS' do
      business.update!(sms_enabled: false)
      expect(SmsService.should_send_invitation?(customer, business, :booking_confirmation)).to be_falsey
    end

    it 'returns false when customer already opted in' do
      customer.update!(phone_opt_in: true)
      expect(SmsService.should_send_invitation?(customer, business, :booking_confirmation)).to be_falsey
    end

    it 'returns false when customer opted out from business' do
      customer.opt_out_from_business!(business)
      expect(SmsService.should_send_invitation?(customer, business, :booking_confirmation)).to be_falsey
    end

    it 'returns false when recent invitation exists' do
      SmsOptInInvitation.create!(
        phone_number: customer.phone,
        business: business,
        context: 'booking_confirmation',
        sent_at: 1.day.ago
      )

      expect(SmsService.should_send_invitation?(customer, business, :booking_confirmation)).to be_falsey
    end

    it 'returns false for marketing context' do
      expect(SmsService.should_send_invitation?(customer, business, :marketing)).to be_falsey
    end
  end

  describe '.send_opt_in_invitation' do
    before do
      allow(SmsService).to receive(:send_message).and_return({ success: true })
    end

    it 'creates invitation record' do
      expect {
        SmsService.send_opt_in_invitation(customer, business, :booking_confirmation)
      }.to change(SmsOptInInvitation, :count).by(1)

      invitation = SmsOptInInvitation.last
      expect(invitation.phone_number).to eq(customer.phone)
      expect(invitation.business).to eq(business)
      expect(invitation.tenant_customer).to eq(customer)
      expect(invitation.context).to eq('booking_confirmation')
    end

    it 'sends SMS with correct message' do
      expected_message = "Hi! #{business.name} tried to send you a booking confirmation. " \
                        "Reply YES to receive SMS from #{business.name} or STOP to opt out. " \
                        "Msg & data rates may apply."

      expect(SmsService).to receive(:send_message).with(
        customer.phone,
        expected_message,
        {
          business_id: business.id,
          tenant_customer_id: customer.id
        }
      ).and_return({ success: true })

      SmsService.send_opt_in_invitation(customer, business, :booking_confirmation)
    end

    it 'logs success when SMS sent successfully' do
      expect(Rails.logger).to receive(:info).with(
        match(/SMS_INVITATION.*Sending invitation to customer #{customer.id}/)
      )
      expect(Rails.logger).to receive(:info).with(
        match(/SMS_INVITATION.*Invitation sent successfully/)
      )

      SmsService.send_opt_in_invitation(customer, business, :booking_confirmation)
    end

    it 'logs error when SMS fails' do
      allow(SmsService).to receive(:send_message).and_return({ success: false, error: 'Failed' })

      expect(Rails.logger).to receive(:error).with(
        match(/SMS_INVITATION.*Failed to send invitation/)
      )

      SmsService.send_opt_in_invitation(customer, business, :booking_confirmation)
    end
  end

  describe '.generate_invitation_message' do
    it 'generates correct message for booking confirmation' do
      message = SmsService.generate_invitation_message(business, :booking_confirmation)
      expect(message).to include("#{business.name} tried to send you a booking confirmation")
      expect(message).to include("Reply YES to receive SMS from #{business.name}")
      expect(message).to include("or STOP to opt out")
    end

    it 'generates correct message for booking reminder' do
      message = SmsService.generate_invitation_message(business, :booking_reminder)
      expect(message).to include("booking reminder")
    end

    it 'generates correct message for order update' do
      message = SmsService.generate_invitation_message(business, :order_update)
      expect(message).to include("order update")
    end

    it 'generates generic message for unknown context' do
      message = SmsService.generate_invitation_message(business, :unknown)
      expect(message).to include("notification")
    end
  end

  describe 'Integration with booking confirmation' do
    it 'sends invitation when customer not opted in' do
      expect(SmsService).to receive(:should_send_invitation?).with(customer, business, :booking_confirmation).and_return(true)
      expect(SmsService).to receive(:send_opt_in_invitation).with(customer, business, :booking_confirmation)

      result = SmsService.send_booking_confirmation(booking)
      expect(result[:success]).to be_falsey
      expect(result[:error]).to include("Customer not opted in")
    end

    it 'does not send invitation when should_send_invitation? returns false' do
      expect(SmsService).to receive(:should_send_invitation?).with(customer, business, :booking_confirmation).and_return(false)
      expect(SmsService).not_to receive(:send_opt_in_invitation)

      result = SmsService.send_booking_confirmation(booking)
      expect(result[:success]).to be_falsey
    end

    it 'sends normal SMS when customer is opted in' do
      customer.update!(phone_opt_in: true)
      user = create(:user, :client, email: customer.email, phone_opt_in: true,
                    notification_preferences: { 'sms_booking_reminder' => true })

      expect(SmsService).not_to receive(:should_send_invitation?)
      expect(SmsService).not_to receive(:send_opt_in_invitation)

      # Mock the actual SMS sending
      allow(SmsService).to receive(:send_message_with_rate_limit).and_return({ success: true })

      result = SmsService.send_booking_confirmation(booking)
      expect(result[:success]).to be_truthy
    end
  end
end