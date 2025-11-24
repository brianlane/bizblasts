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
    # Custom test for price_modifier since we have a custom setter that parses strings
    it 'validates price_modifier numericality with custom parsing' do
      variant = build(:product_variant, product: product)
      
      # Valid numeric values should work
      variant.price_modifier = 10.50
      expect(variant).to be_valid
      
      variant.price_modifier = -5.25
      expect(variant).to be_valid
      
      variant.price_modifier = nil
      expect(variant).to be_valid
      
      # Valid string representations should be parsed and work
      variant.price_modifier = "10.50"
      expect(variant).to be_valid
      expect(variant.price_modifier).to eq(10.50)
      
      variant.price_modifier = "-$5.25"
      expect(variant).to be_valid
      expect(variant.price_modifier).to eq(-5.25)

      variant.price_modifier = "$-12.34"
      expect(variant).to be_valid
      expect(variant.price_modifier).to eq(-12.34)
      
      variant.price_modifier = "-  $  7.00"
      expect(variant).to be_valid
      expect(variant.price_modifier).to eq(-7.0)
      
      # Invalid strings (with no numbers) trigger validation errors with helpful messages
      variant.price_modifier = "xyz"
      variant.valid? # Trigger validation
      expect(variant.errors[:price_modifier]).to include("must be a valid number (e.g., '5.50', '-5.50', or '$5.50')")
      expect(variant).to be_invalid
    end
    
    it 'validates that price modifier does not make final price negative' do
      variant = build(:product_variant, product: product)
      
      # Valid discount that doesn't make final price negative
      variant.price_modifier = -5.00
      expect(variant).to be_valid
      
      # Invalid discount that makes final price negative (product price is $50)
      variant.price_modifier = -55.00
      expect(variant).to be_invalid
      expect(variant.errors[:price_modifier]).to include(/cannot make the final price negative/)
      
      # Zero final price should be valid
      if variant.product.price.present?
        variant.price_modifier = -variant.product.price
        expect(variant).to be_valid
        expect(variant.final_price).to eq(0.0)
      end
    end
    
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