require 'rails_helper'

RSpec.describe PlatformReferral, type: :model do
  describe 'associations' do
    it { should belong_to(:referrer_business).class_name('Business') }
    it { should belong_to(:referred_business).class_name('Business') }
  end

  describe 'validations' do
    subject { build(:platform_referral) }
    
    # Note: referral_code presence is ensured by before_validation callback, not validation
    it { should validate_uniqueness_of(:referral_code) }
    
    it { should validate_presence_of(:status) }
    it { should validate_inclusion_of(:status).in_array(['pending', 'qualified', 'rewarded']) }
    

  end

  describe 'scopes' do
    let(:business) { create(:business) }
    let!(:pending_referrals) { create_list(:platform_referral, 2, referrer_business: business, status: 'pending') }
    let!(:qualified_referrals) { create_list(:platform_referral, 3, referrer_business: business, status: 'qualified') }
    let!(:rewarded_referrals) { create_list(:platform_referral, 1, referrer_business: business, status: 'rewarded') }
    
    describe '.where(referrer_business: business)' do
      it 'returns referrals where business is the referrer' do
        referrals = PlatformReferral.where(referrer_business: business)
        expect(referrals.count).to eq(6)
        expect(referrals.pluck(:referrer_business_id)).to all(eq(business.id))
      end
    end
    
    describe '.qualified' do
      it 'returns only qualified referrals' do
        referrals = PlatformReferral.qualified
        expect(referrals.count).to eq(3)
        expect(referrals.pluck(:status)).to all(eq('qualified'))
      end
    end
    
    describe '.rewarded' do
      it 'returns only rewarded referrals' do
        referrals = PlatformReferral.rewarded
        expect(referrals.count).to eq(1)
        expect(referrals.pluck(:status)).to all(eq('rewarded'))
      end
    end
    
    describe '.recent' do
      it 'returns referrals ordered by creation date' do
        recent_referral = create(:platform_referral, referrer_business: business)
        
        referrals = PlatformReferral.where(referrer_business: business).recent
        expect(referrals.first).to eq(recent_referral)
      end
    end
  end

  describe 'callbacks' do
    describe 'before_validation' do
      it 'generates referral code on create' do
        referral = build(:platform_referral, referral_code: nil)
        
        expect { referral.save! }.to change { referral.referral_code }.from(nil)
        expect(referral.referral_code).to match(/^BIZ-.+-[A-Z0-9]{6}$/)
      end
    end
  end

  describe 'status transitions' do
    let(:referral) { create(:platform_referral, status: 'pending') }
    
    describe '#mark_qualified!' do
      it 'transitions from pending to qualified' do
        expect { referral.mark_qualified! }.to change { referral.status }.from('pending').to('qualified')
        expect(referral.qualification_met_at).to be_within(1.second).of(Time.current)
      end
      
      it 'sets qualification_met_at timestamp' do
        referral.mark_qualified!
        expect(referral.qualification_met_at).to be_present
        expect(referral.qualification_met_at).to be_within(1.second).of(Time.current)
      end
    end
    
    describe '#mark_rewarded!' do
      it 'transitions from qualified to rewarded' do
        referral.update!(status: 'qualified')
        
        expect { referral.mark_rewarded! }.to change { referral.status }.from('qualified').to('rewarded')
        expect(referral.reward_issued_at).to be_within(1.second).of(Time.current)
      end
      
      it 'sets reward_issued_at timestamp' do
        referral.update!(status: 'qualified')
        referral.mark_rewarded!
        
        expect(referral.reward_issued_at).to be_present
        expect(referral.reward_issued_at).to be_within(1.second).of(Time.current)
      end
    end
  end

  describe 'instance methods' do
    let(:referral) { create(:platform_referral) }
    
    describe '#pending?' do
      it 'returns true for pending status' do
        referral.update!(status: 'pending')
        expect(referral.pending?).to be true
      end
      
      it 'returns false for non-pending status' do
        referral.update!(status: 'qualified')
        expect(referral.pending?).to be false
      end
    end
    
    describe '#qualified?' do
      it 'returns true for qualified status' do
        referral.update!(status: 'qualified')
        expect(referral.qualified?).to be true
      end
      
      it 'returns false for non-qualified status' do
        referral.update!(status: 'pending')
        expect(referral.qualified?).to be false
      end
    end
    
    describe '#rewarded?' do
      it 'returns true for rewarded status' do
        referral.update!(status: 'rewarded')
        expect(referral.rewarded?).to be true
      end
      
      it 'returns false for non-rewarded status' do
        referral.update!(status: 'qualified')
        expect(referral.rewarded?).to be false
      end
    end
  end

  describe 'custom validations' do
    describe 'self-referral prevention' do
      it 'allows different businesses' do
        referrer = create(:business)
        referred = create(:business)
        referral = build(:platform_referral, 
                        referrer_business: referrer, 
                        referred_business: referred)
        
        expect(referral).to be_valid
      end
    end
  end
end 