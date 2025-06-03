require 'rails_helper'

RSpec.describe TenantCustomerPolicy do
  subject { described_class }

  let(:business) { create(:business) }
  let(:manager)  { create(:user, :manager, business: business) }
  let(:staff)    { create(:user, :staff, business: business) }
  let(:client)   { create(:user, :client) }
  let(:other_business) { create(:business) }
  let(:other_manager)  { create(:user, :manager, business: other_business) }
  let(:customer)       { create(:tenant_customer, business: business) }

  describe '#index?' do
    it 'allows manager and staff' do
      expect(TenantCustomerPolicy.new(manager, customer).index?).to be_truthy
      expect(TenantCustomerPolicy.new(staff, customer).index?).to be_truthy
    end

    it 'denies access to client and other business manager' do
      expect(TenantCustomerPolicy.new(client, customer).index?).to be_falsey
      expect(TenantCustomerPolicy.new(other_manager, customer).index?).to be_falsey
    end
  end

  describe '#show?' do
    it 'follows index? authorization' do
      expect(TenantCustomerPolicy.new(manager, customer).show?).to eq(TenantCustomerPolicy.new(manager, customer).index?)
    end
  end

  describe '#create?' do
    it 'follows index? authorization' do
      expect(TenantCustomerPolicy.new(manager, customer).create?).to eq(TenantCustomerPolicy.new(manager, customer).index?)
    end
  end

  describe '#new?' do
    it 'follows create? authorization' do
      expect(TenantCustomerPolicy.new(manager, customer).new?).to eq(TenantCustomerPolicy.new(manager, customer).create?)
    end
  end

  describe '#update?' do
    it 'allows manager and staff for same business' do
      expect(TenantCustomerPolicy.new(manager, customer).update?).to be_truthy
      expect(TenantCustomerPolicy.new(staff, customer).update?).to be_truthy
    end

    it 'denies client and other business manager' do
      expect(TenantCustomerPolicy.new(client, customer).update?).to be_falsey
      expect(TenantCustomerPolicy.new(other_manager, customer).update?).to be_falsey
    end
  end

  describe '#edit?' do
    it 'follows update? authorization' do
      expect(TenantCustomerPolicy.new(manager, customer).edit?).to eq(TenantCustomerPolicy.new(manager, customer).update?)
    end
  end

  describe '#destroy?' do
    it 'follows update? authorization' do
      expect(TenantCustomerPolicy.new(manager, customer).destroy?).to eq(TenantCustomerPolicy.new(manager, customer).update?)
    end
  end

  describe "Scope" do
    let!(:other_customer) { create(:tenant_customer, business: other_business) }

    it "includes only customers for the user's business" do
      scope = Pundit.policy_scope!(manager, TenantCustomer)
      expect(scope).to include(customer)
      expect(scope).not_to include(other_customer)
    end
  end
end 