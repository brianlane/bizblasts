require 'rails_helper'

RSpec.describe EstimatePolicy do
  subject { described_class }

  let(:business) { create(:business) }
  let(:manager) { create(:user, :manager, business: business) }
  let(:other_manager) { create(:user, :manager) }
  let(:customer_user) { create(:user, :client) }
  let(:customer) { create(:tenant_customer, business: business, user: customer_user) }
  let(:estimate) { create(:estimate, business: business, tenant_customer: customer) }
  let(:other_estimate) { create(:estimate) }


  describe "Scope" do
    it "returns all estimates for a business manager" do
      scope = Pundit.policy_scope!(manager, Estimate)
      expect(scope).to include(estimate)
      expect(scope).not_to include(other_estimate)
    end

    it "returns estimates for the correct client" do
      scope = Pundit.policy_scope!(customer_user, Estimate)
      expect(scope).to include(estimate)
      expect(scope).not_to include(other_estimate)
    end
  end

  describe '#show?' do
    it 'grants access to business managers of the same business' do
      expect(described_class.new(manager, estimate).show?).to be_truthy
    end

    it 'denies access to other managers' do
      expect(described_class.new(other_manager, estimate).show?).to be_falsey
    end

    it 'grants access to the assigned customer' do
      expect(described_class.new(customer_user, estimate).show?).to be_truthy
    end
  end

  describe '#create?' do
    it 'grants access to business managers' do
      expect(described_class.new(manager, Estimate.new(business: business)).create?).to be_truthy
    end

    it 'denies access to other users' do
      expect(described_class.new(other_manager, Estimate.new(business: business)).create?).to be_falsey
      expect(described_class.new(customer_user, Estimate.new(business: business)).create?).to be_falsey
    end
  end

  describe '#update?' do
    it 'grants access to business managers of the same business' do
      expect(described_class.new(manager, estimate).update?).to be_truthy
    end

    it 'denies access to other managers' do
      expect(described_class.new(other_manager, estimate).update?).to be_falsey
    end
  end

  describe '#send_to_customer?' do
    it 'grants access to business managers of the same business' do
      expect(described_class.new(manager, estimate).send_to_customer?).to be_truthy
    end

    it 'denies access to other managers' do
      expect(described_class.new(other_manager, estimate).send_to_customer?).to be_falsey
    end
  end
end 