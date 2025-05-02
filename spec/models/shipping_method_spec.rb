require 'rails_helper'

RSpec.describe ShippingMethod, type: :model do
  let(:business) { create(:business) } # Assuming you have a business factory

  describe 'associations' do
    it { should belong_to(:business) }
    it { should have_many(:orders) }
    it { should have_many(:invoices) } # If invoices use shipping
  end

  describe 'validations' do
    subject { build(:shipping_method, business: business) }
    it { should validate_presence_of(:name) }
    it { should validate_uniqueness_of(:name).scoped_to(:business_id) }
    it { should validate_presence_of(:cost) }
    it { should validate_numericality_of(:cost).is_greater_than_or_equal_to(0) }
  end

  describe 'scopes' do
    let!(:active_method) { create(:shipping_method, business: business, active: true) }
    let!(:inactive_method) { create(:shipping_method, business: business, active: false) }

    it '.active returns only active methods' do
      expect(ShippingMethod.active).to contain_exactly(active_method)
      expect(ShippingMethod.active).not_to include(inactive_method)
    end
  end

  # Add tests for TenantScoped concern if not covered elsewhere
  # ...
end 