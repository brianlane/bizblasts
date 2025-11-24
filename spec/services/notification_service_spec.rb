require 'rails_helper'

RSpec.describe NotificationService, type: :service do
  let(:business) { create(:business, sms_enabled: true, sms_marketing_enabled: true) }
  let(:customer) { create(:tenant_customer, business: business, phone: '+15551234567', phone_opt_in: true) }
  let(:booking) { create(:booking, business: business, tenant_customer: customer) }
  let(:invoice) { create(:invoice, business: business, tenant_customer: customer) }
  let(:order) { create(:order, business: business, tenant_customer: customer) }

  before do
    allow(Rails.application.config).to receive(:sms_enabled).and_return(true)
    allow(BookingMailer).to receive_message_chain(:confirmation, :deliver_later)
    allow(SmsService).to receive(:send_booking_confirmation).and_return(true)
  end

  describe '.booking_confirmation' do
    context 'when customer can receive both email and SMS' do
      before do
        allow(customer).to receive(:can_receive_email?).with(:booking).and_return(true)
        allow(customer).to receive(:can_receive_sms?).with(:booking).and_return(true)
      end

      it 'sends both email and SMS notifications' do
        expect(BookingMailer).to receive(:confirmation).with(booking)
        expect(SmsService).to receive(:send_booking_confirmation).with(booking).and_return(true)
        
        NotificationService.booking_confirmation(booking)
      end

      it 'returns success status for both channels' do
        result = NotificationService.booking_confirmation(booking)
        expect(result[:email]).to be true
        expect(result[:sms]).to be true
      end
    end

    context 'when customer can only receive email' do
      before do
        allow(customer).to receive(:can_receive_email?).with(:booking).and_return(true)
        allow(customer).to receive(:can_receive_sms?).with(:booking).and_return(false)
      end

      it 'sends only email notification' do
        expect(BookingMailer).to receive(:confirmation).with(booking)
        expect(SmsService).to receive(:send_booking_confirmation).with(booking).and_return({ success: false })
        
        NotificationService.booking_confirmation(booking)
      end
    end

    context 'when customer cannot receive any notifications' do
      before do
        allow(customer).to receive(:can_receive_email?).with(:booking).and_return(false)
        allow(customer).to receive(:can_receive_sms?).with(:booking).and_return(false)
      end

      it 'does not send any notifications' do
        expect(BookingMailer).not_to receive(:confirmation)
        expect(SmsService).to receive(:send_booking_confirmation).with(booking).and_return({ success: false })
        
        result = NotificationService.booking_confirmation(booking)
        expect(result[:email]).to be false
        expect(result[:sms]).to be false
      end
    end

    context 'when email fails but SMS succeeds' do
      before do
        allow(customer).to receive(:can_receive_email?).with(:booking).and_return(true)
        allow(customer).to receive(:can_receive_sms?).with(:booking).and_return(true)
        allow(BookingMailer).to receive(:confirmation).and_raise(StandardError, 'Email service down')
      end

      it 'continues with SMS notification' do
        expect(SmsService).to receive(:send_booking_confirmation).with(booking).and_return(true)
        
        result = NotificationService.booking_confirmation(booking)
        expect(result[:email]).to be false
        expect(result[:sms]).to be true
      end

      it 'logs the email error' do
        expect(Rails.logger).to receive(:error).with(/Email failed/)
        NotificationService.booking_confirmation(booking)
      end
    end
  end

  describe '.invoice_created' do
    before do
      allow(InvoiceMailer).to receive_message_chain(:invoice_created, :deliver_later)
      allow(SmsService).to receive(:send_invoice_created).and_return(true)
    end

    context 'when customer can receive transactional SMS' do
      before do
        allow(customer).to receive(:can_receive_email?).with(:payment).and_return(true)
        allow(customer).to receive(:can_receive_sms?).with(:transactional).and_return(true)
      end

      it 'sends both email and SMS notifications' do
        expect(InvoiceMailer).to receive(:invoice_created).with(invoice)
        expect(SmsService).to receive(:send_invoice_created).with(invoice).and_return(true)
        
        NotificationService.invoice_created(invoice)
      end
    end
  end

  describe '.marketing_campaign' do
    let(:campaign) { create(:marketing_campaign, business: business) }

    before do
      allow(MarketingMailer).to receive_message_chain(:campaign, :deliver_later)
      allow(SmsService).to receive(:send_marketing_campaign).and_return(true)
    end

    context 'when customer can receive marketing communications' do
      before do
        allow(customer).to receive(:can_receive_email?).with(:marketing).and_return(true)
        allow(customer).to receive(:can_receive_sms?).with(:marketing).and_return(true)
      end

      it 'sends both email and SMS marketing' do
        expect(MarketingMailer).to receive(:campaign).with(customer, campaign)
        expect(SmsService).to receive(:send_marketing_campaign).with(campaign, customer).and_return(true)
        
        NotificationService.marketing_campaign(campaign, customer)
      end
    end

    context 'when customer opted out of marketing SMS' do
      before do
        allow(customer).to receive(:can_receive_email?).with(:marketing).and_return(true)
        allow(customer).to receive(:can_receive_sms?).with(:marketing).and_return(false)
      end

      it 'sends only email marketing' do
        expect(MarketingMailer).to receive(:campaign).with(customer, campaign)
        expect(SmsService).to receive(:send_marketing_campaign).with(campaign, customer).and_return({ success: false })
        
        NotificationService.marketing_campaign(campaign, customer)
      end
    end
  end

  describe '.business_new_booking' do
    let(:business_user) { create(:user, :manager, business: business, phone: '+15559876543') }

    before do
      allow(BusinessMailer).to receive_message_chain(:new_booking_notification, :deliver_later)
      allow(SmsService).to receive(:send_business_new_booking).and_return(true)
      allow(business).to receive_message_chain(:users, :where, :first).and_return(business_user)
    end

    context 'when business user can receive notifications' do
      before do
        allow(business_user).to receive(:can_receive_email?).with(:booking).and_return(true)
        allow(business_user).to receive(:can_receive_email?).with(:customer).and_return(true)
        allow(business_user).to receive(:can_receive_sms?).with(:booking).and_return(true)
      end

      it 'sends notifications to business user' do
        expect(BusinessMailer).to receive(:new_booking_notification).with(booking)
        expect(SmsService).to receive(:send_business_new_booking).with(booking, business_user).and_return(true)
        
        NotificationService.business_new_booking(booking)
      end
    end

    context 'when no business manager found' do
      before do
        allow(business).to receive_message_chain(:users, :where, :first).and_return(nil)
      end

      it 'does not send any notifications' do
        expect(BusinessMailer).not_to receive(:new_booking_notification)
        expect(SmsService).not_to receive(:send_business_new_booking)
        
        NotificationService.business_new_booking(booking)
      end
    end
  end
end