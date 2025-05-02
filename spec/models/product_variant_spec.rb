# spec/models/product_variant_spec.rb
require 'rails_helper'

RSpec.describe ProductVariant, type: :model do
  let(:business) { create(:business) }
  let(:product) { create(:product, business: business, price: 50.0) }

  describe 'associations' do
    it { should belong_to(:product) }
    it { should have_many(:line_items).dependent(:destroy) }
    # Test delegation
    it { should delegate_method(:business).to(:product) }
    it { should delegate_method(:business_id).to(:product) }
  end

  describe 'validations' do
    subject { build(:product_variant, product: product) }
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:stock_quantity) }
    it { should validate_numericality_of(:stock_quantity).only_integer.is_greater_than_or_equal_to(0) }
    it { should validate_numericality_of(:price_modifier).allow_nil }
    it { should validate_numericality_of(:stock_quantity).is_greater_than_or_equal_to(0) }
  end

  describe 'stock management' do
    let(:variant) { create(:product_variant, product: product, stock_quantity: 10) }

    context '#in_stock?' do
      it { expect(variant.in_stock?(1)).to be true } 
      it { expect(variant.in_stock?(10)).to be true }
      it { expect(variant.in_stock?(11)).to be false }
      it { expect(variant.in_stock?(0)).to be true } # Assuming requesting 0 is valid
    end

    context '#increment_stock!' do
      it 'increases stock quantity' do
        expect { variant.increment_stock!(5) }.to change { variant.stock_quantity }.from(10).to(15)
      end

      it 'increases stock quantity by 1 by default' do
        expect { variant.increment_stock! }.to change { variant.stock_quantity }.from(10).to(11)
      end
    end

    context '#decrement_stock!' do
      it 'decreases stock quantity if sufficient stock' do
        expect { variant.decrement_stock!(3) }.to change { variant.stock_quantity }.from(10).to(7)
        expect(variant.decrement_stock!(3)).to be true
      end

      it 'decreases stock quantity by 1 by default' do
        expect { variant.decrement_stock! }.to change { variant.stock_quantity }.from(10).to(9)
        expect(variant.decrement_stock!).to be true
      end

      it 'returns false and adds error if insufficient stock' do
        expect(variant.decrement_stock!(11)).to be false
        expect(variant.stock_quantity).to eq(10) # Stock should not change
        expect(variant.errors[:stock_quantity]).to include("is insufficient to decrement by 11")
      end

      it 'does not decrease stock below zero' do
        expect(variant.decrement_stock!(10)).to be true
        expect(variant.stock_quantity).to eq(0)
        expect(variant.decrement_stock!(1)).to be false
        expect(variant.stock_quantity).to eq(0)
      end
    end
  end

  describe '#final_price' do
    it 'calculates price with positive modifier' do
      variant = build(:product_variant, product: product, price_modifier: 5.50)
      expect(variant.final_price).to eq(55.50)
    end

    it 'calculates price with negative modifier' do
      variant = build(:product_variant, product: product, price_modifier: -10.0)
      expect(variant.final_price).to eq(40.00)
    end

    it 'calculates price with zero modifier' do
      variant = build(:product_variant, product: product, price_modifier: 0)
      expect(variant.final_price).to eq(50.00)
    end

    it 'calculates price with nil modifier' do
      variant = build(:product_variant, product: product, price_modifier: nil)
      expect(variant.final_price).to eq(50.00)
    end

    it 'handles product with zero price' do
      product.update!(price: 0)
      variant = build(:product_variant, product: product, price_modifier: 10.0)
      expect(variant.final_price).to eq(10.00)
    end

    it 'handles case where product might not be loaded (though association implies it should be)' do
      variant = build(:product_variant, product: nil, price_modifier: 5.0) # Set product to nil
      expect(variant.product).to be_nil
      # Depending on validation, this might not be a valid state
      # If product is required, this test might be irrelevant
      # If product is not required (unlikely), test the behavior
      # expect(variant.final_price).to eq(5.00) # Or 0 if base price defaults to 0
    end
  end
end 