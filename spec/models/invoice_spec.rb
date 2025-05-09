require 'rails_helper'

RSpec.describe Invoice, type: :model do
  let(:business) { create(:business) }
  let(:tenant_customer) { create(:tenant_customer, business: business) }
  let(:shipping_method) { create(:shipping_method, business: business, cost: 10.0) }
  let(:tax_rate_no_shipping) { create(:tax_rate, business: business, rate: 0.1, applies_to_shipping: false) }
  let(:tax_rate_with_shipping) { create(:tax_rate, business: business, rate: 0.08, applies_to_shipping: true) }

  describe 'associations' do
    it { should belong_to(:business) }
    it { should belong_to(:tenant_customer) }
    it { should belong_to(:booking).optional }
    it { should belong_to(:promotion).optional }
    it { should belong_to(:shipping_method).optional }
    it { should belong_to(:tax_rate).optional }
    it { should have_many(:line_items).dependent(:destroy) }
  end

  describe 'validations' do
    subject { build(:invoice, tenant_customer: tenant_customer, business: business) }
    it { should validate_presence_of(:amount) }
    it { should validate_numericality_of(:amount).is_greater_than_or_equal_to(0) }
    it { should validate_presence_of(:total_amount) }
    it { should validate_numericality_of(:total_amount).is_greater_than_or_equal_to(0) }
    it { should validate_presence_of(:due_date) }
    it { should validate_presence_of(:status) }
    it { should validate_presence_of(:invoice_number) }
    it { should validate_uniqueness_of(:invoice_number).scoped_to(:business_id) }
    it { should validate_numericality_of(:original_amount).is_greater_than_or_equal_to(0).allow_nil }
    it { should validate_numericality_of(:discount_amount).is_greater_than_or_equal_to(0).allow_nil }
  end

  describe 'callbacks' do
    context 'before_save :calculate_totals' do
      let(:product1) { create(:product, business: business, price: 20.00) }
      let(:variant1) { create(:product_variant, product: product1, price_modifier: 0) }
      let(:product2) { create(:product, business: business, price: 15.00) }
      let(:variant2) { create(:product_variant, product: product2, price_modifier: 0) }
      let!(:invoice) { create(:invoice, tenant_customer: tenant_customer, business: business, shipping_method: shipping_method, line_items: []) }

      before do
        create(:line_item, lineable: invoice, product_variant: variant1, quantity: 2) # Total: 40.00
        create(:line_item, lineable: invoice, product_variant: variant2, quantity: 1) # Total: 15.00
        invoice.reload
        # Line items total = 55.00
        # Shipping = 10.00
      end

      # it 'calculates totals correctly with no tax rate' do
      #   invoice.tax_rate = nil
      #   invoice.save!
      #   expect(invoice.original_amount).to be_within(0.01).of(55.00)
      #   expect(invoice.amount).to be_within(0.01).of(55.00)
      #   expect(invoice.tax_amount).to be_within(0.01).of(0.00)
      #   expect(invoice.total_amount).to be_within(0.01).of(55.00) # 55 + 0
      # end

      # it 'calculates totals correctly with tax rate not applied to shipping' do
      #   invoice.tax_rate = tax_rate_no_shipping # 10% on 55.00 = 5.50
      #   invoice.save!
      #   expect(invoice.original_amount).to be_within(0.01).of(55.00)
      #   expect(invoice.amount).to be_within(0.01).of(55.00)
      #   expect(invoice.tax_amount).to be_within(0.01).of(5.50)
      #   expect(invoice.total_amount).to be_within(0.01).of(60.50) # 55 + 5.50
      # end

      # it 'calculates totals correctly with discount' do
      #   invoice.tax_rate = tax_rate_no_shipping # 10% on discounted amount
      #   invoice.discount_amount = 10.00
      #   invoice.save!
      #   expect(invoice.original_amount).to be_within(0.01).of(55.00)
      #   expect(invoice.amount).to be_within(0.01).of(45.00) # 55 - 10
      #   expect(invoice.tax_amount).to be_within(0.01).of(4.50) # 10% on 45
      #   expect(invoice.total_amount).to be_within(0.01).of(49.50) # 45 + 4.50
      # end
    end
  end
end 