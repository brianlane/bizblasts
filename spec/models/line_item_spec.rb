require 'rails_helper'

RSpec.describe LineItem, type: :model do
  let(:business) { create(:business) }
  let(:other_business) { create(:business) }
  let(:order) { create(:order, business: business) }
  let(:invoice) { create(:invoice, business: business) } # Assuming invoice factory
  let(:product) { create(:product, business: business, price: 25.0, variants_count: 1) }
  let(:variant) { product.product_variants.last }
  let(:other_product) { create(:product, business: other_business, variants_count: 1) }
  let(:other_variant) { other_product.product_variants.first }
  let(:service) { create(:service, business: business) }

  describe 'associations' do
    it { should belong_to(:lineable).optional } # Polymorphic
    #it { should belong_to(:product_variant).optional } # Optional for service line items
    # Conditional validation handled in custom validations context
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

      it 'handles nil lineable on create as optional, but requires product_variant' do
        line_item_no_lineable = build(:line_item, lineable: nil, product_variant: variant)
        # lineable is optional on create, so should be valid
        expect(line_item_no_lineable).to be_valid
        line_item_no_variant = build(:line_item, lineable: order, product_variant: nil)
        # missing product_variant for product line item should be invalid
        expect(line_item_no_variant).not_to be_valid
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

  describe 'custom validations' do
    let(:order) { create(:order, business: business) }

    context 'product_or_service_presence' do
      it 'is invalid when neither product nor service selected' do
        li = build(:line_item, lineable: order, product_variant: nil, service: nil)
        expect(li).not_to be_valid
        expect(li.errors[:base]).to include('Line items must have either a product or a service selected')
      end

      it 'is invalid when both product and service selected' do
        svc = create(:service, business: business)
        stf = create(:staff_member, business: business)
        li = build(:line_item, lineable: order, product_variant: variant, service: svc, staff_member: stf)
        expect(li).not_to be_valid
        expect(li.errors[:base]).to include('Line items cannot have both product and service selected')
      end

      it 'is invalid when service present without staff_member' do
        svc = create(:service, business: business)
        li = build(:line_item, lineable: order, product_variant: nil, service: svc, staff_member: nil)
        expect(li).not_to be_valid
        expect(li.errors[:staff_member]).to include('must be selected for service line items')
      end

      it 'is valid when service and staff_member present' do
        svc = create(:service, business: business)
        stf = create(:staff_member, business: business)
        li = build(:line_item, lineable: order, product_variant: nil, service: svc, staff_member: stf)
        expect(li).to be_valid
      end
    end

    describe '#product? and #service?' do
      it 'returns true for product items and false for service' do
        product_li = build(:line_item, lineable: order, product_variant: variant, service: nil)
        expect(product_li.product?).to be true
        expect(product_li.service?).to be false
      end

      it 'returns true for service items and false for product' do
        svc = create(:service, business: business)
        stf = create(:staff_member, business: business)
        service_li = build(:line_item, lineable: order, product_variant: nil, service: svc, staff_member: stf)
        expect(service_li.service?).to be true
        expect(service_li.product?).to be false
      end
    end

    context 'stock_sufficiency' do
      let(:variant_with_stock) { create(:product_variant, product: create(:product, business: business), stock_quantity: 2) }

      it 'is invalid when quantity exceeds available stock' do
        li = build(:line_item, lineable: order, product_variant: variant_with_stock, quantity: 5)
        expect(li).not_to be_valid
        expect(li.errors[:quantity]).to include("for #{variant_with_stock.name} is not sufficient. Only #{variant_with_stock.stock_quantity} available.")
      end

      it 'is valid when quantity does not exceed available stock' do
        li = build(:line_item, lineable: order, product_variant: variant_with_stock, quantity: 2)
        expect(li).to be_valid
      end
    end
  end
end 