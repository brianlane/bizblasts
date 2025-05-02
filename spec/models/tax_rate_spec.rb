# spec/models/tax_rate_spec.rb
require 'rails_helper'

RSpec.describe TaxRate, type: :model do
  let(:business) { create(:business) } # Assuming you have a business factory

  describe 'associations' do
    it { should belong_to(:business) }
    it { should have_many(:orders) }
    it { should have_many(:invoices) } # If invoices use tax rates
  end

  describe 'validations' do
    subject { build(:tax_rate, business: business) }
    it { should validate_presence_of(:name) }
    it { should validate_uniqueness_of(:name).scoped_to(:business_id) }
    it { should validate_presence_of(:rate) }
    it { should validate_numericality_of(:rate).is_greater_than_or_equal_to(0).is_less_than_or_equal_to(1) }
    # Optional validations
    # it { should validate_presence_of(:region) } # if region is mandatory
    # it { should validate_inclusion_of(:applies_to_shipping).in_array([true, false]) } # Should be in model
  end

  describe '#calculate_tax' do
    let(:tax_rate_8_percent) { build(:tax_rate, rate: 0.08) }
    let(:tax_rate_10_5_percent) { build(:tax_rate, rate: 0.105) }

    it 'calculates tax correctly for a given amount' do
      expect(tax_rate_8_percent.calculate_tax(100.00)).to eq(8.00)
      expect(tax_rate_8_percent.calculate_tax(55.50)).to eq(4.44) # 55.50 * 0.08 = 4.44
    end

    it 'calculates tax correctly with more decimal places in rate' do
      expect(tax_rate_10_5_percent.calculate_tax(100.00)).to eq(10.50)
      expect(tax_rate_10_5_percent.calculate_tax(75.00)).to eq(7.88) # 75.00 * 0.105 = 7.875 -> rounds to 7.88
    end

    it 'returns 0 if amount is 0' do
      expect(tax_rate_8_percent.calculate_tax(0)).to eq(0)
    end
  end

  # Add tests for TenantScoped concern if not covered elsewhere
  # ...
end 