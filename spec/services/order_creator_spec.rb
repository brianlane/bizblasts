require 'rails_helper'

RSpec.describe OrderCreator do
  let(:business) { create(:business) }
  let(:tenant_customer) { create(:tenant_customer, business: business) }
  let(:product1) { create(:product, business: business, price: 20.00) }
  let(:variant1) { create(:product_variant, product: product1, price_modifier: 0, stock_quantity: 5) }
  let(:product2) { create(:product, business: business, price: 15.00) }
  let(:variant2) { create(:product_variant, product: product2, price_modifier: 0, stock_quantity: 3) }

  describe '.create' do
    context 'with valid parameters' do
        let(:order_params) do
            attributes_for(:order).merge(
              tenant_customer_id: tenant_customer.id,  # Explicitly add the tenant_customer_id
              line_items_attributes: [
                { product_variant_id: variant1.id, quantity: 2 },
                { product_variant_id: variant2.id, quantity: 1 }
              ]
            )
        end

      
      it 'creates a new order' do
        expect { OrderCreator.create(order_params) }.to change(Order, :count).by(1)
      end

      it 'decrements stock for each line item' do
        expect { OrderCreator.create(order_params) }.to change { variant1.reload.stock_quantity }.by(-2)
                                                   .and change { variant2.reload.stock_quantity }.by(-1)
      end

      it 'returns the created order' do
        order = OrderCreator.create(order_params)
        expect(order).to be_a(Order)
        expect(order).to be_persisted
      end
    end

    context 'with insufficient stock' do
      let(:order_params) do
        attributes_for(:order).merge(
          tenant_customer_id: tenant_customer.id,
          line_items_attributes: [
            { product_variant_id: variant1.id, quantity: 10 } # Exceeds available stock
          ]
        )
      end

      it 'does not create a new order' do
        expect { OrderCreator.create(order_params) }.not_to change(Order, :count)
      end

      it 'does not decrement stock' do
        expect { OrderCreator.create(order_params) }.not_to change { variant1.reload.stock_quantity }
      end

      it 'returns the unsaved order with errors' do
        order = OrderCreator.create(order_params)
        expect(order).to be_a(Order)
        expect(order).not_to be_persisted
        expect(order.errors[:base]).to include("Insufficient stock for #{variant1.name}")
      end
    end

    context 'with invalid order parameters' do
        let(:order_params) do
            attributes_for(:order, tenant_customer_id: nil).merge(
              # Note: no tenant_customer_id here to make it invalid
              line_items_attributes: [
                { product_variant_id: variant1.id, quantity: 1 }
              ]
            )
        end

      it 'does not create a new order' do
        expect { OrderCreator.create(order_params) }.not_to change(Order, :count)
      end

      it 'does not decrement stock' do
        expect { OrderCreator.create(order_params) }.not_to change { variant1.reload.stock_quantity }
      end

      it 'returns the unsaved order with errors' do
        order = OrderCreator.create(order_params)
        expect(order).to be_a(Order)
        expect(order).not_to be_persisted
        expect(order.errors[:tenant_customer]).to include("can't be blank")
      end
    end
  end
end 