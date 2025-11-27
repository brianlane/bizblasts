require 'rails_helper'

RSpec.describe EstimateItem, type: :model do
  let(:business) { create(:business) }
  let(:estimate) { create(:estimate, business: business) }

  describe 'enums' do
    it 'defines item_type enum' do
      expect(EstimateItem.item_types).to eq({
        'service' => 0,
        'product' => 1,
        'labor' => 2,
        'part' => 3
      })
    end
  end

  describe 'validations' do
    context 'labor items' do
      it 'requires hours and hourly_rate' do
        item = build(:estimate_item, estimate: estimate, item_type: :labor, hours: nil, hourly_rate: nil)
        expect(item).not_to be_valid
        expect(item.errors[:hours]).to be_present
        expect(item.errors[:hourly_rate]).to be_present
      end

      it 'validates hours is greater than 0' do
        item = build(:estimate_item, estimate: estimate, item_type: :labor, hours: 0, hourly_rate: 50)
        expect(item).not_to be_valid
      end
    end
  end

  describe 'scopes' do
    let!(:required_item) { create(:estimate_item, estimate: estimate, optional: false) }
    let!(:optional_selected) { create(:estimate_item, estimate: estimate, optional: true, customer_selected: true) }
    let!(:optional_declined) { create(:estimate_item, estimate: estimate, optional: true, customer_declined: true) }

    it 'required scope returns non-optional items' do
      expect(EstimateItem.required).to include(required_item)
      expect(EstimateItem.required).not_to include(optional_selected)
    end

    it 'optional_items scope returns optional items' do
      expect(EstimateItem.optional_items).to include(optional_selected, optional_declined)
      expect(EstimateItem.optional_items).not_to include(required_item)
    end

    it 'customer_selected scope returns selected items' do
      expect(EstimateItem.customer_selected).to include(optional_selected)
      expect(EstimateItem.customer_selected).not_to include(optional_declined)
    end

    it 'included_in_totals scope excludes declined items' do
      expect(EstimateItem.included_in_totals).to include(required_item, optional_selected)
      expect(EstimateItem.included_in_totals).not_to include(optional_declined)
    end
  end

  describe '#calculate_total' do
    context 'for standard items (service, product, part)' do
      it 'calculates total as qty × cost_rate' do
        item = build(:estimate_item, estimate: estimate, item_type: :service, qty: 3, cost_rate: 25)
        item.valid?
        expect(item.total).to eq(75)
      end
    end

    context 'for labor items' do
      it 'calculates total as hours × hourly_rate' do
        item = build(:estimate_item, estimate: estimate, item_type: :labor, hours: 2.5, hourly_rate: 60)
        item.valid?
        expect(item.total).to eq(150)
      end
    end
  end

  describe '#tax_amount' do
    it 'calculates tax correctly' do
      item = create(:estimate_item, estimate: estimate, qty: 2, cost_rate: 50, tax_rate: 10)
      expect(item.tax_amount).to eq(10) # (50 × 2) × 10% = 10
    end

    it 'returns 0 for declined optional items' do
      item = create(:estimate_item, estimate: estimate, optional: true,
                    customer_declined: true, qty: 2, cost_rate: 50, tax_rate: 10)
      expect(item.tax_amount).to eq(0)
    end
  end

  describe '#display_name' do
    it 'returns "Labor: description" for labor items' do
      item = create(:estimate_item, estimate: estimate, item_type: :labor,
                    description: 'Installation work', hours: 2, hourly_rate: 50)
      expect(item.display_name).to eq('Labor: Installation work')
    end

    it 'returns "Part: description" for part items' do
      item = create(:estimate_item, estimate: estimate, item_type: :part,
                    description: 'Replacement part')
      expect(item.display_name).to eq('Part: Replacement part')
    end
  end

  describe '#included_in_totals?' do
    it 'returns true for required items' do
      item = create(:estimate_item, estimate: estimate, optional: false)
      expect(item.included_in_totals?).to be true
    end

    it 'returns true for selected optional items' do
      item = create(:estimate_item, estimate: estimate, optional: true, customer_selected: true)
      expect(item.included_in_totals?).to be true
    end

    it 'returns false for declined optional items' do
      item = create(:estimate_item, estimate: estimate, optional: true, customer_declined: true)
      expect(item.included_in_totals?).to be false
    end
  end

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

    it 'sets position based on existing items' do
      create(:estimate_item, estimate: estimate, position: 1)
      create(:estimate_item, estimate: estimate, position: 2)

      item = build(:estimate_item, estimate: estimate, position: nil)
      item.valid?
      expect(item.position).to eq(3)
    end

    it 'sets customer_selected to true by default' do
      item = build(:estimate_item, estimate: estimate, customer_selected: nil)
      item.valid?
      expect(item.customer_selected).to be true
    end
  end

  describe '#sync_from_associations for labor items' do
    it 'sets cost_rate to hourly_rate' do
      item = build(:estimate_item, estimate: estimate, item_type: :labor,
                   hours: 2.5, hourly_rate: 60, cost_rate: nil)
      item.valid?
      expect(item.cost_rate).to eq(60)
    end

    it 'sets qty to ceil of hours with minimum 1' do
      item = build(:estimate_item, estimate: estimate, item_type: :labor,
                   hours: 2.3, hourly_rate: 60, qty: nil)
      item.valid?
      expect(item.qty).to eq(3) # ceil(2.3)
    end
  end
end
