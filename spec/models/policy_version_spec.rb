# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PolicyVersion, type: :model do
  subject { build(:policy_version) }
  
  describe 'validations' do
    it { should validate_presence_of(:policy_type) }
    it { should validate_presence_of(:version) }
    it { should validate_presence_of(:effective_date) }
    it { should validate_inclusion_of(:policy_type).in_array(PolicyVersion::POLICY_TYPES) }
    it { should validate_uniqueness_of(:version).scoped_to(:policy_type) }
  end
  
  describe 'scopes' do
    let!(:active_policy) { create(:policy_version, policy_type: 'privacy_policy', active: true) }
    let!(:inactive_policy) { create(:policy_version, policy_type: 'terms_of_service', active: false) }
    let!(:notification_policy) { create(:policy_version, requires_notification: true) }
    
    describe '.active' do
      it 'returns only active policies' do
        expect(PolicyVersion.active).to include(active_policy)
        expect(PolicyVersion.active).not_to include(inactive_policy)
      end
    end
    
    describe '.for_policy_type' do
      it 'returns policies for the specified type' do
        expect(PolicyVersion.for_policy_type('privacy_policy')).to include(active_policy)
        expect(PolicyVersion.for_policy_type('privacy_policy')).not_to include(inactive_policy)
      end
    end
    
    describe '.requiring_notification' do
      it 'returns policies requiring notification' do
        expect(PolicyVersion.requiring_notification).to include(notification_policy)
      end
    end
  end
  
  describe '.current_version' do
    let!(:active_policy) { create(:policy_version, policy_type: 'privacy_policy', active: true) }
    let!(:inactive_policy) { create(:policy_version, policy_type: 'privacy_policy', active: false) }
    
    it 'returns the active version for the policy type' do
      expect(PolicyVersion.current_version('privacy_policy')).to eq(active_policy)
    end
    
    it 'returns nil if no active version exists' do
      expect(PolicyVersion.current_version('nonexistent_policy')).to be_nil
    end
  end
  
  describe '.current_versions' do
    let!(:privacy_policy) { create(:policy_version, policy_type: 'privacy_policy', active: true) }
    let!(:terms_policy) { create(:policy_version, policy_type: 'terms_of_service', active: true) }
    
    it 'returns a hash of current versions for all policy types' do
      versions = PolicyVersion.current_versions
      expect(versions['privacy_policy']).to eq(privacy_policy)
      expect(versions['terms_of_service']).to eq(terms_policy)
      expect(versions['acceptable_use_policy']).to be_nil
      expect(versions['return_policy']).to be_nil
    end
  end
  
  describe '#activate!' do
    let!(:old_version) { create(:policy_version, policy_type: 'privacy_policy', version: 'v1.0', active: true) }
    let(:new_version) { create(:policy_version, policy_type: 'privacy_policy', version: 'v2.0', active: false, requires_notification: true) }
    let!(:user1) { create(:user, role: :client) }
    let!(:user2) { create(:user, role: :client) } # Changed to client to avoid business requirement
    
    before do
      allow(PolicyMailer).to receive(:policy_update_notification).and_return(double(deliver_later: true))
    end
    
    it 'deactivates other versions of the same policy type' do
      new_version.activate!
      
      expect(old_version.reload.active).to be false
      expect(new_version.reload.active).to be true
    end
    
    it 'marks users for reacceptance when requires_notification is true' do
      expect {
        new_version.activate!
      }.to change { user1.reload.requires_policy_acceptance }.from(false).to(true)
        .and change { user2.reload.requires_policy_acceptance }.from(false).to(true)
    end
    
    it 'sends email notifications for privacy policy and terms of service' do
      expect(PolicyMailer).to receive(:policy_update_notification).with(user1, [new_version]).and_return(double(deliver_later: true))
      expect(PolicyMailer).to receive(:policy_update_notification).with(user2, [new_version]).and_return(double(deliver_later: true))
      
      new_version.activate!
    end
    
    context 'when policy does not require notification' do
      let(:new_version) { create(:policy_version, policy_type: 'privacy_policy', version: 'v2.0', active: false, requires_notification: false) }
      
      it 'does not mark users for reacceptance' do
        expect {
          new_version.activate!
        }.not_to change { user1.reload.requires_policy_acceptance }
      end
    end
    
    context 'for return policy' do
      let(:new_version) { create(:policy_version, policy_type: 'return_policy', version: 'v2.0', active: false, requires_notification: true) }
      let!(:business_user) { create(:user, role: :client) } # Create as client first
      
      before do
        # Create a business and associate the user
        business = create(:business)
        business_user.update!(business: business, role: :manager)
      end
      
      it 'only marks business users for reacceptance' do
        new_version.activate!
        
        expect(user1.reload.requires_policy_acceptance).to be false # client
        expect(business_user.reload.requires_policy_acceptance).to be true # manager
      end
    end
  end
  
  describe '#policy_name' do
    it 'returns humanized policy name' do
      policy = build(:policy_version, policy_type: 'privacy_policy')
      expect(policy.policy_name).to eq('Privacy Policy')
    end
  end
  
  describe '#policy_path' do
    it 'returns correct paths for each policy type' do
      expect(build(:policy_version, policy_type: 'terms_of_service').policy_path).to eq('/terms')
      expect(build(:policy_version, policy_type: 'privacy_policy').policy_path).to eq('/privacypolicy')
      expect(build(:policy_version, policy_type: 'acceptable_use_policy').policy_path).to eq('/acceptableusepolicy')
      expect(build(:policy_version, policy_type: 'return_policy').policy_path).to eq('/returnpolicy')
    end
  end
end 