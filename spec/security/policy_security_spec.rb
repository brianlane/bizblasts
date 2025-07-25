# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Pundit Policy Security', type: :policy do
  let!(:business1) { create(:business, hostname: 'business1') }
  let!(:business2) { create(:business, hostname: 'business2') }
  let!(:manager1) { create(:user, :manager, business: business1) }
  let!(:manager2) { create(:user, :manager, business: business2) }
  let!(:staff1) { create(:user, :staff, business: business1) }
  let!(:client) { create(:user, :client) }
  let!(:admin) { create(:admin_user) }

  describe BusinessManager::Settings::IntegrationCredentialPolicy do
    let!(:credential1) { create(:integration_credential, business: business1) }
    let!(:credential2) { create(:integration_credential, business: business2) }

    context 'for business manager' do
      subject { described_class.new(manager1, credential1) }

      it { is_expected.to permit_action(:index) }
      it { is_expected.to permit_action(:show) }
      it { is_expected.to permit_action(:create) }
      it { is_expected.to permit_action(:update) }
      it { is_expected.to permit_action(:destroy) }
    end

    context 'for manager accessing other business credential' do
      subject { described_class.new(manager1, credential2) }

      it { is_expected.to forbid_action(:show) }
      it { is_expected.to forbid_action(:update) }
      it { is_expected.to forbid_action(:destroy) }
    end

    context 'for staff user' do
      subject { described_class.new(staff1, credential1) }

      it { is_expected.to forbid_action(:index) }
      it { is_expected.to forbid_action(:show) }
      it { is_expected.to forbid_action(:create) }
      it { is_expected.to forbid_action(:update) }
      it { is_expected.to forbid_action(:destroy) }
    end

    context 'for client user' do
      subject { described_class.new(client, credential1) }

      it { is_expected.to forbid_action(:index) }
      it { is_expected.to forbid_action(:show) }
      it { is_expected.to forbid_action(:create) }
      it { is_expected.to forbid_action(:update) }
      it { is_expected.to forbid_action(:destroy) }
    end
  end

  describe BusinessManager::Settings::LocationPolicy do
    let!(:location1) { create(:location, business: business1) }
    let!(:location2) { create(:location, business: business2) }

    context 'for business manager' do
      subject { described_class.new(manager1, location1) }

      it { is_expected.to permit_action(:index) }
      it { is_expected.to permit_action(:show) }
      it { is_expected.to permit_action(:create) }
      it { is_expected.to permit_action(:update) }
      it { is_expected.to permit_action(:destroy) }
    end

    context 'for manager accessing other business location' do
      subject { described_class.new(manager1, location2) }

      it { is_expected.to forbid_action(:show) }
      it { is_expected.to forbid_action(:update) }
      it { is_expected.to forbid_action(:destroy) }
    end
  end

  describe Admin::BusinessPolicy do
    context 'for admin user' do
      subject { described_class.new(admin, business1) }

      it { is_expected.to permit_action(:index) }
      it { is_expected.to permit_action(:show) }
      it { is_expected.to permit_action(:create) }
      it { is_expected.to permit_action(:update) }
      it { is_expected.to permit_action(:destroy) }
    end

    context 'for regular user pretending to be admin' do
      subject { described_class.new(manager1, business1) }

      it { is_expected.to forbid_action(:index) }
      it { is_expected.to forbid_action(:show) }
      it { is_expected.to forbid_action(:create) }
      it { is_expected.to forbid_action(:update) }
      it { is_expected.to forbid_action(:destroy) }
    end
  end

  describe 'Authorization failure logging' do
    let!(:credential) { create(:integration_credential, business: business2) }

    it 'logs authorization failures' do
      policy = BusinessManager::Settings::IntegrationCredentialPolicy.new(manager1, credential)
      
      expect(SecureLogger).to receive(:security_event).with(
        'authorization_failure',
        hash_including(
          user_id: manager1.id,
          user_type: 'User',
          action: :show,
          resource: 'IntegrationCredential',
          resource_id: credential.id
        )
      )

      policy.show?
    end
  end
end