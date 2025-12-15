require 'rails_helper'

RSpec.describe TenantCustomer, 'Business-specific SMS opt-out', type: :model do
  let(:business1) { create(:business, sms_enabled: true) }
  let(:business2) { create(:business, sms_enabled: true) }
  let(:customer1) { create(:tenant_customer, business: business1, phone: '+15551234567', phone_opt_in: true) }
  let(:customer2) { create(:tenant_customer, business: business2, phone: '+15551234567', phone_opt_in: true) }

  describe '#opted_out_from_business?' do
    it 'returns false when not opted out from any business' do
      expect(customer1.opted_out_from_business?(business1)).to be_falsey
    end

    it 'returns false when sms_opted_out_businesses is nil' do
      customer1.update!(sms_opted_out_businesses: nil)
      expect(customer1.opted_out_from_business?(business1)).to be_falsey
    end

    it 'returns true when opted out from specific business' do
      customer1.update!(sms_opted_out_businesses: [business1.id])
      expect(customer1.opted_out_from_business?(business1)).to be_truthy
    end

    it 'returns false when opted out from different business' do
      customer1.update!(sms_opted_out_businesses: [business2.id])
      expect(customer1.opted_out_from_business?(business1)).to be_falsey
    end
  end

  describe '#opt_out_from_business!' do
    it 'adds business ID to opted out list' do
      customer1.opt_out_from_business!(business1)
      expect(customer1.sms_opted_out_businesses).to include(business1.id)
    end

    it 'does not add duplicate business IDs' do
      customer1.opt_out_from_business!(business1)
      customer1.opt_out_from_business!(business1)
      expect(customer1.sms_opted_out_businesses.count(business1.id)).to eq(1)
    end

    it 'can opt out from multiple businesses' do
      customer1.opt_out_from_business!(business1)
      customer1.opt_out_from_business!(business2)
      expect(customer1.sms_opted_out_businesses).to include(business1.id, business2.id)
    end

    it 'initializes sms_opted_out_businesses when nil' do
      customer1.update!(sms_opted_out_businesses: nil)
      customer1.opt_out_from_business!(business1)
      expect(customer1.sms_opted_out_businesses).to eq([business1.id])
    end
  end

  describe '#opt_in_to_business!' do
    before do
      customer1.update!(sms_opted_out_businesses: [business1.id, business2.id])
    end

    it 'removes business ID from opted out list' do
      customer1.opt_in_to_business!(business1)
      expect(customer1.sms_opted_out_businesses).not_to include(business1.id)
      expect(customer1.sms_opted_out_businesses).to include(business2.id)
    end

    it 'does nothing when business not in opted out list' do
      another_business = create(:business)
      customer1.opt_in_to_business!(another_business)
      expect(customer1.sms_opted_out_businesses).to eq([business1.id, business2.id])
    end

    it 'does nothing when sms_opted_out_businesses is nil' do
      customer1.update!(sms_opted_out_businesses: nil)
      expect { customer1.opt_in_to_business!(business1) }.not_to raise_error
    end
  end

  describe '#can_receive_invitation_from?' do
    it 'returns false when opted out from business' do
      customer1.opt_out_from_business!(business1)
      expect(customer1.can_receive_invitation_from?(business1)).to be_falsey
    end

    it 'returns true when not opted out and no recent invitation' do
      expect(customer1.can_receive_invitation_from?(business1)).to be_truthy
    end

    it 'returns false when recent invitation exists' do
      SmsOptInInvitation.create!(
        phone_number: customer1.phone,
        business: business1,
        context: 'booking_confirmation',
        sent_at: 1.day.ago
      )

      expect(customer1.can_receive_invitation_from?(business1)).to be_falsey
    end
  end

  describe '#can_receive_sms? with business opt-out' do
    it 'returns false when opted out from specific business' do
      customer1.opt_out_from_business!(business1)
      expect(customer1.can_receive_sms?(:booking)).to be_falsey
    end

    it 'returns true when not opted out from business' do
      # Ensure customer is properly set up to receive SMS
      user = create(:user, :client, email: customer1.email, phone_opt_in: true,
                    notification_preferences: { 'sms_booking_reminder' => true })

      expect(customer1.can_receive_sms?(:booking)).to be_truthy
    end

    it 'business-specific opt-out takes precedence over other checks' do
      # Even if customer is opted in globally, business-specific opt-out should block
      customer1.opt_out_from_business!(business1)

      expect(customer1.can_receive_sms?(:booking)).to be_falsey
    end
  end

  describe 'logging' do
    it 'logs opt-out action' do
      expect(Rails.logger).to receive(:info).with(
        match(/SMS_OPT_OUT.*Customer #{customer1.id} opted out from business #{business1.id}/)
      )
      customer1.opt_out_from_business!(business1)
    end

    it 'logs opt-in action' do
      customer1.update!(sms_opted_out_businesses: [business1.id])

      expect(Rails.logger).to receive(:info).with(
        match(/SMS_OPT_IN.*Customer #{customer1.id} opted back in to business #{business1.id}/)
      )
      customer1.opt_in_to_business!(business1)
    end
  end
end