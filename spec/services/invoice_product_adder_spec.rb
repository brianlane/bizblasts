require 'rails_helper'

RSpec.describe InvoiceProductAdder do
  let(:business) { create(:business) }
  let(:tenant_customer) { create(:tenant_customer, business: business) }
  let(:invoice) { create(:invoice, tenant_customer: tenant_customer, business: business) }
  let(:product) { create(:product, business: business, price: 20.00) }
  let(:variant) { create(:product_variant, product: product, price_modifier: 0, stock_quantity: 5) }

  describe '.add' do
    context 'with sufficient stock' do
      it 'adds a new line item to the invoice' do
        expect { InvoiceProductAdder.add(invoice, variant, 2) }.to change(invoice.line_items, :count).by(1)
      end

      it 'decrements stock for the variant' do
        expect { InvoiceProductAdder.add(invoice, variant, 2) }.to change { variant.reload.stock_quantity }.by(-2)
      end

      it 'returns the created line item' do
        line_item = InvoiceProductAdder.add(invoice, variant, 2)
        expect(line_item).to be_a(LineItem)
        expect(line_item).to be_persisted
      end
    end

    context 'with insufficient stock' do
      it 'does not add a new line item to the invoice' do
        expect { InvoiceProductAdder.add(invoice, variant, 10) }.not_to change(invoice.line_items, :count)
      end

      it 'does not decrement stock for the variant' do
        expect { InvoiceProductAdder.add(invoice, variant, 10) }.not_to change { variant.reload.stock_quantity }
      end

      it 'returns false' do
        result = InvoiceProductAdder.add(invoice, variant, 10)
        expect(result).to be false
      end

      it 'adds an error to the invoice' do
        InvoiceProductAdder.add(invoice, variant, 10)
        expect(invoice.errors[:base]).to include("Insufficient stock for #{variant.name}")
      end
    end

    context 'when invoice fails to save' do
      before do
        # Simulate a validation error on the invoice
        allow_any_instance_of(Invoice).to receive(:save).and_return(false)
      end

      it 'does not add a new line item to the invoice' do
        expect { InvoiceProductAdder.add(invoice, variant, 1) }.not_to change(invoice.line_items, :count)
      end

      it 'does not decrement stock for the variant' do
        expect { InvoiceProductAdder.add(invoice, variant, 1) }.not_to change { variant.reload.stock_quantity }
      end

      it 'returns false' do
        result = InvoiceProductAdder.add(invoice, variant, 1)
        expect(result).to be false
      end
    end
  end
end 