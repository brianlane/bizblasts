require 'rails_helper'

RSpec.describe Category, type: :model do
  let(:business) { create(:business) } # Assuming you have a business factory

  describe 'associations' do
    it { should belong_to(:business) }
    it { should have_many(:products) }
  end

  describe 'validations' do
    # Create instance for uniqueness check
    subject { build(:category, business: business) }
    it { should validate_presence_of(:name) }
    it { should validate_uniqueness_of(:name).scoped_to(:business_id) }
  end

  # Add tests for TenantScoped concern if not covered elsewhere
  # describe 'TenantScoped concern' do
  #   it 'should belong to a business' do
  #     category = build(:category, business: nil)
  #     expect(category).not_to be_valid
  #     expect(category.errors[:business]).to include("must exist")
  #   end

  #   it 'should default scope to current tenant' do
  #     business1 = create(:business)
  #     business2 = create(:business)
  #     category1 = create(:category, business: business1)
  #     category2 = create(:category, business: business2)

  #     ActsAsTenant.with_tenant(business1) do
  #       expect(Category.count).to eq(1)
  #       expect(Category.first).to eq(category1)
  #     end
  #   end
  # end
end 