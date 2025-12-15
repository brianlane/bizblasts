require 'rails_helper'

RSpec.describe SmsOptInInvitation, type: :model do
  let(:business) { create(:business, sms_enabled: true) }
  let(:customer) { create(:tenant_customer, business: business, phone: '+15551234567') }

  describe 'validations' do
    it 'requires phone_number' do
      invitation = SmsOptInInvitation.new(business: business, context: 'booking_confirmation')
      expect(invitation).not_to be_valid
      expect(invitation.errors[:phone_number]).to include("can't be blank")
    end

    it 'requires valid phone_number format' do
      invitation = SmsOptInInvitation.new(
        business: business,
        phone_number: 'invalid',
        context: 'booking_confirmation'
      )
      expect(invitation).not_to be_valid
      expect(invitation.errors[:phone_number]).to include("is invalid")
    end

    it 'requires context' do
      invitation = SmsOptInInvitation.new(business: business, phone_number: '+15551234567')
      expect(invitation).not_to be_valid
      expect(invitation.errors[:context]).to include("can't be blank")
    end

    it 'requires sent_at' do
      invitation = SmsOptInInvitation.new(
        business: business,
        phone_number: '+15551234567',
        context: 'booking_confirmation'
      )
      expect(invitation).not_to be_valid
      expect(invitation.errors[:sent_at]).to include("can't be blank")
    end
  end

  describe 'associations' do
    it 'belongs to business' do
      expect(SmsOptInInvitation.reflect_on_association(:business).macro).to eq(:belongs_to)
    end

    it 'belongs to tenant_customer optionally' do
      association = SmsOptInInvitation.reflect_on_association(:tenant_customer)
      expect(association.macro).to eq(:belongs_to)
      expect(association.options[:optional]).to be_truthy
    end
  end

  describe '.recent_invitation_sent?' do
    it 'returns false when no recent invitation exists' do
      expect(SmsOptInInvitation.recent_invitation_sent?('+15551234567', business.id)).to be_falsey
    end

    it 'returns true when recent invitation exists' do
      SmsOptInInvitation.create!(
        phone_number: '+15551234567',
        business: business,
        context: 'booking_confirmation',
        sent_at: 1.day.ago
      )

      expect(SmsOptInInvitation.recent_invitation_sent?('+15551234567', business.id)).to be_truthy
    end

    it 'returns false when invitation is older than specified days' do
      SmsOptInInvitation.create!(
        phone_number: '+15551234567',
        business: business,
        context: 'booking_confirmation',
        sent_at: 31.days.ago
      )

      expect(SmsOptInInvitation.recent_invitation_sent?('+15551234567', business.id, 30)).to be_falsey
    end
  end

  describe '#record_response!' do
    let(:invitation) do
      SmsOptInInvitation.create!(
        phone_number: '+15551234567',
        business: business,
        context: 'booking_confirmation',
        sent_at: Time.current
      )
    end

    it 'records YES response as successful opt-in' do
      invitation.record_response!('YES')

      invitation.reload
      expect(invitation.response).to eq('YES')
      expect(invitation.responded_at).to be_within(1.second).of(Time.current)
      expect(invitation.successful_opt_in).to be_truthy
    end

    it 'records STOP response as not successful' do
      invitation.record_response!('STOP')

      invitation.reload
      expect(invitation.response).to eq('STOP')
      expect(invitation.successful_opt_in).to be_falsey
    end
  end

  describe '.opt_in_response?' do
    it 'recognizes YES as opt-in' do
      expect(SmsOptInInvitation.opt_in_response?('YES')).to be_truthy
    end

    it 'recognizes START as opt-in' do
      expect(SmsOptInInvitation.opt_in_response?('START')).to be_truthy
    end

    it 'recognizes STOP as not opt-in' do
      expect(SmsOptInInvitation.opt_in_response?('STOP')).to be_falsey
    end

    it 'handles case insensitivity' do
      expect(SmsOptInInvitation.opt_in_response?('yes')).to be_truthy
      expect(SmsOptInInvitation.opt_in_response?('start')).to be_truthy
    end
  end

  describe 'analytics methods' do
    before do
      # Create mix of invitations
      SmsOptInInvitation.create!(
        phone_number: '+15551111111',
        business: business,
        context: 'booking_confirmation',
        sent_at: 5.days.ago,
        responded_at: 4.days.ago,
        response: 'YES',
        successful_opt_in: true
      )

      SmsOptInInvitation.create!(
        phone_number: '+15552222222',
        business: business,
        context: 'booking_reminder',
        sent_at: 3.days.ago,
        responded_at: 2.days.ago,
        response: 'STOP',
        successful_opt_in: false
      )

      SmsOptInInvitation.create!(
        phone_number: '+15553333333',
        business: business,
        context: 'booking_confirmation',
        sent_at: 1.day.ago
        # No response
      )
    end

    describe '.conversion_rate' do
      it 'calculates correct conversion rate' do
        # 1 successful out of 3 total = 33.33%
        expect(SmsOptInInvitation.conversion_rate(30)).to eq(33.33)
      end
    end

    describe '.response_rate' do
      it 'calculates correct response rate' do
        # 2 responses out of 3 total = 66.67%
        expect(SmsOptInInvitation.response_rate(30)).to eq(66.67)
      end
    end
  end
end