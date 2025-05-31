# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PolicyAcceptance, type: :model do
  let(:user) { create(:user) }
  let(:policy_version) { create(:policy_version, policy_type: 'privacy_policy', version: 'v1.0') }
  
  describe 'associations' do
    it { should belong_to(:user) }
  end
  
  describe 'validations' do
    it { should validate_presence_of(:policy_type) }
    it { should validate_presence_of(:policy_version) }
    it { should validate_presence_of(:accepted_at) }
    it { should validate_inclusion_of(:policy_type).in_array(PolicyAcceptance::POLICY_TYPES) }
  end
  
  describe 'scopes' do
    let!(:acceptance1) { create(:policy_acceptance, user: user, policy_type: 'privacy_policy') }
    let!(:acceptance2) { create(:policy_acceptance, policy_type: 'terms_of_service') }
    
    describe '.for_user' do
      it 'returns acceptances for the specified user' do
        expect(PolicyAcceptance.for_user(user)).to include(acceptance1)
        expect(PolicyAcceptance.for_user(user)).not_to include(acceptance2)
      end
    end
    
    describe '.for_policy_type' do
      it 'returns acceptances for the specified policy type' do
        expect(PolicyAcceptance.for_policy_type('privacy_policy')).to include(acceptance1)
        expect(PolicyAcceptance.for_policy_type('privacy_policy')).not_to include(acceptance2)
      end
    end
  end
  
  describe '.has_accepted_policy?' do
    context 'when user has accepted the policy' do
      let!(:acceptance) { create(:policy_acceptance, user: user, policy_type: 'privacy_policy', policy_version: 'v1.0') }
      
      it 'returns true without version check' do
        expect(PolicyAcceptance.has_accepted_policy?(user, 'privacy_policy')).to be true
      end
      
      it 'returns true with matching version' do
        expect(PolicyAcceptance.has_accepted_policy?(user, 'privacy_policy', 'v1.0')).to be true
      end
      
      it 'returns false with non-matching version' do
        expect(PolicyAcceptance.has_accepted_policy?(user, 'privacy_policy', 'v2.0')).to be false
      end
    end
    
    context 'when user has not accepted the policy' do
      it 'returns false' do
        expect(PolicyAcceptance.has_accepted_policy?(user, 'privacy_policy')).to be false
      end
    end
  end
  
  describe '.record_acceptance' do
    let(:request) { double('request', remote_ip: '127.0.0.1', user_agent: 'Test Browser') }
    
    it 'creates a new policy acceptance record' do
      expect {
        PolicyAcceptance.record_acceptance(user, 'privacy_policy', 'v1.0', request)
      }.to change(PolicyAcceptance, :count).by(1)
    end
    
    it 'sets the correct attributes' do
      acceptance = PolicyAcceptance.record_acceptance(user, 'privacy_policy', 'v1.0', request)
      
      expect(acceptance.user).to eq(user)
      expect(acceptance.policy_type).to eq('privacy_policy')
      expect(acceptance.policy_version).to eq('v1.0')
      expect(acceptance.ip_address).to eq('127.0.0.1')
      expect(acceptance.user_agent).to eq('Test Browser')
      expect(acceptance.accepted_at).to be_within(1.second).of(Time.current)
    end
    
    it 'works without request object' do
      acceptance = PolicyAcceptance.record_acceptance(user, 'privacy_policy', 'v1.0')
      
      expect(acceptance.user).to eq(user)
      expect(acceptance.policy_type).to eq('privacy_policy')
      expect(acceptance.policy_version).to eq('v1.0')
      expect(acceptance.ip_address).to be_nil
      expect(acceptance.user_agent).to be_nil
    end
  end
end 