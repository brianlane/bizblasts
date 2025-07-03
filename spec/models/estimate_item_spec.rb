require 'rails_helper'

RSpec.describe EstimateItem, type: :model do
  describe 'callbacks and calculations' do
    it 'defaults tax_rate to 0.0 and calculates total' do
      item = build(:estimate_item, qty: 2, cost_rate: '5.00', tax_rate: nil)
      expect(item.tax_rate).to be_nil
      item.valid?  # triggers set_defaults and calculate_total
      expect(item.tax_rate).to eq(0.0)
      expect(item.total).to eq(10.0)
    end

    it 'calculates correct tax_amount' do
      item = build(:estimate_item, qty: 3, cost_rate: '10.00', tax_rate: '5.0')
      item.valid?
      # tax_amount = (10 * 3) * (5/100) = 30 * 0.05 = 1.5
      expect(item.tax_amount).to eq(1.5)
    end
  end
end
