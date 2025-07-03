require 'rails_helper'

RSpec.describe Estimate, type: :model do
  describe '#calculate_totals' do
    it 'calculates subtotal, taxes, and total correctly' do
      estimate = build(:estimate)
      item1 = build(:estimate_item, estimate: estimate, qty: 2, cost_rate: '10.00', tax_rate: '5.0')
      item2 = build(:estimate_item, estimate: estimate, qty: 1, cost_rate: '20.00', tax_rate: '10.0')
      estimate.estimate_items = [item1, item2]
      estimate.valid?

      expect(estimate.subtotal).to eq(40.0)
      # item1 tax_amount = (10 * 2) * 0.05 = 1.0; item2 = (20 * 1) * 0.10 = 2.0; sum=3.0
      expect(estimate.taxes).to eq(3.0)
      expect(estimate.total).to eq(43.0)
    end
  end

  describe 'customer validation' do
    it 'skips contact validations when tenant_customer_id is present' do
      estimate = build(:estimate, tenant_customer_id: 1, first_name: '', last_name: '', email: '', phone: '', address: '', city: '', state: '', zip: '')
      expect(estimate).to be_valid
    end
  end
end
