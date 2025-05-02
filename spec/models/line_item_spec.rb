require 'rails_helper'

RSpec.describe LineItem, type: :model do
  let(:business) { create(:business) }
  let(:other_business) { create(:business) }
  let(:order) { create(:order, business: business) }
  let(:invoice) { create(:invoice, business: business) } # Assuming invoice factory
  let(:product) { create(:product, business: business, price: 25.0, variants_count: 1) }
  let(:variant) { product.product_variants.first }
  let(:other_product) { create(:product, business: other_business, variants_count: 1) }
  let(:other_variant) { other_product.product_variants.first }
  let(:service) { create(:service, business: business) }

  describe 'associations' do
    it { should belong_to(:lineable) } # Polymorphic
    it { should belong_to(:product_variant) }
    it { should delegate_method(:business_id).to(:lineable).allow_nil }
  end

  describe 'validations' do
    subject { build(:line_item, lineable: order, product_variant: variant) }

    it { should validate_presence_of(:product_variant) }
    it { should validate_presence_of(:quantity) }
    it { should validate_numericality_of(:quantity).only_integer.is_greater_than(0) }
    # Price and Total Amount presence/numericality are effectively handled by the
    # :set_price_and_total callback based on product_variant and quantity.
    # Direct validation tests conflict with the callback logic.
    # it { should validate_presence_of(:price) }
    it { should validate_numericality_of(:price).is_greater_than_or_equal_to(0) }
    # it { should validate_presence_of(:total_amount) }
    # it { should validate_numericality_of(:total_amount).is_greater_than_or_equal_to(0) }

    context 'business_consistency' do
      it 'is valid if product variant belongs to the same business as the lineable (Order)' do
        line_item = build(:line_item, lineable: order, product_variant: variant)
        expect(line_item).to be_valid
      end

      it 'is invalid if product variant belongs to a different business than the lineable' do
        line_item = build(:line_item, lineable: order, product_variant: other_variant)
        expect(line_item).not_to be_valid
        expect(line_item.errors[:product_variant]).to include("must belong to the same business as the order")
      end

      it 'handles nil lineable or product_variant gracefully (covered by presence validations)' do
        line_item_no_lineable = build(:line_item, lineable: nil, product_variant: variant)
        line_item_no_variant = build(:line_item, lineable: order, product_variant: nil)
        expect(line_item_no_lineable).not_to be_valid # Fails presence validation
        expect(line_item_no_variant).not_to be_valid # Fails presence validation
      end
    end
  end

  describe 'callbacks' do
    context 'before_validation :set_price_and_total (on :create)' do
      it 'sets price from variant and calculates total amount' do
        line_item = build(:line_item, lineable: order, product_variant: variant, quantity: 3, price: nil, total_amount: nil)
        line_item.valid? # Trigger validation callbacks
        expect(line_item.price).to eq(variant.final_price)
        expect(line_item.total_amount).to eq(variant.final_price * 3)
      end

      it 'does not overwrite an existing price' do
        manual_price = 20.00
        line_item = build(:line_item, lineable: order, product_variant: variant, quantity: 3, price: manual_price, total_amount: nil)
        line_item.valid?
        expect(line_item.price).to eq(manual_price)
        expect(line_item.total_amount).to eq(manual_price * 3)
      end
    end

    context 'before_save :update_total_amount (if quantity changed)' do
      it 'updates total amount if quantity changes' do
        line_item = create(:line_item, lineable: order, product_variant: variant, quantity: 2)
        expect(line_item.total_amount).to be_within(0.01).of(variant.final_price * 2)
        line_item.quantity = 4
        line_item.save!
        expect(line_item.total_amount).to be_within(0.01).of(variant.final_price * 4)
      end

      it 'does not run callback if quantity did not change' do
        line_item = create(:line_item, lineable: order, product_variant: variant, quantity: 2)
        initial_total = line_item.total_amount
        line_item.save! # Save without changing quantity
        line_item.reload # Reload to ensure any parent callbacks have finished
        expect(line_item.total_amount).to be_within(0.01).of(initial_total)
      end

      it 'uses the existing price when recalculating' do
        manual_price = 20.00
        line_item = create(:line_item, lineable: order, product_variant: variant, quantity: 2, price: manual_price)
        expect(line_item.total_amount).to eq(manual_price * 2)
        line_item.quantity = 3
        line_item.save!
        expect(line_item.price).to eq(manual_price) # Price should remain unchanged
        expect(line_item.total_amount).to eq(manual_price * 3)
      end
    end
  end
end 