require 'rails_helper'

RSpec.describe Product, type: :model do
  describe 'stock management functionality' do
    let(:business) { create(:business) }
    let(:product) { create(:product, business: business, stock_quantity: 0, variants_count: 0) }

    describe '#in_stock?' do
      context 'when stock management is enabled' do
        before do 
          business.update!(stock_management_enabled: true)
          product.reload
        end

        it 'returns true when sufficient stock is available' do
          product.update!(stock_quantity: 10)
          # Update variant stock as well since the product has a default variant
          product.product_variants.first.update!(stock_quantity: 10) if product.has_variants?
          expect(product.in_stock?(5)).to be true
        end

        it 'returns false when insufficient stock is available' do
          product.update!(stock_quantity: 3)
          expect(product.in_stock?(5)).to be false
        end

        context 'with variants' do
          let!(:variant1) { create(:product_variant, product: product, stock_quantity: 5) }
          let!(:variant2) { create(:product_variant, product: product, stock_quantity: 10) }

          it 'returns true when total variant stock is sufficient' do
            expect(product.in_stock?(12)).to be true
          end

          it 'returns false when total variant stock is insufficient' do
            expect(product.in_stock?(20)).to be false
          end
        end
      end

      context 'when stock management is disabled' do
        before do
          business.update!(stock_management_enabled: false)
          product.reload
        end

        it 'always returns true regardless of stock quantity' do
          product.update!(stock_quantity: 0)
          expect(product.in_stock?(100)).to be true
        end

        context 'with variants' do
          let!(:variant) { create(:product_variant, product: product, stock_quantity: 0) }

          it 'always returns true regardless of variant stock' do
            expect(product.in_stock?(100)).to be true
          end
        end
      end
    end

    describe '#visible_to_customers?' do
      before { product.update!(active: true, hide_when_out_of_stock: true) }

      context 'when stock management is enabled' do
        before do
          business.update!(stock_management_enabled: true)
          product.reload
        end

        it 'returns false when out of stock and hide_when_out_of_stock is true' do
          product.update!(stock_quantity: 0)
          expect(product.visible_to_customers?).to be false
        end

        it 'returns true when in stock' do
          product.update!(stock_quantity: 5)
          # Update variant stock as well since the product has a default variant
          product.product_variants.first.update!(stock_quantity: 5) if product.has_variants?
          expect(product.visible_to_customers?).to be true
        end
      end

      context 'when stock management is disabled' do
        before do
          business.update!(stock_management_enabled: false)
          product.reload
        end

        it 'returns true even when stock is 0' do
          product.update!(stock_quantity: 0)
          expect(product.visible_to_customers?).to be true
        end
      end
    end

    describe 'stock_quantity validation' do
      context 'when stock management is enabled' do
        before do
          business.update!(stock_management_enabled: true)
          product.reload
        end

        it 'validates stock_quantity when product has no variants' do
          # Destroy any default variants that might have been created
          product.product_variants.destroy_all
          product.reload
          
          product.stock_quantity = -1
          expect(product).to be_invalid
          expect(product.errors[:stock_quantity]).to include('must be greater than or equal to 0')
        end
      end

      context 'when stock management is disabled' do
        before do
          business.update!(stock_management_enabled: false)
          product.reload
        end

        it 'does not validate stock_quantity' do
          product.stock_quantity = -1
          expect(product).to be_valid
        end
      end
    end

    describe '#can_be_subscribed?' do
      before { product.update!(active: true, subscription_enabled: true) }

      context 'when stock management is enabled' do
        before do
          business.update!(stock_management_enabled: true)
          product.reload
        end

        it 'returns false when out of stock' do
          product.update!(stock_quantity: 0)
          expect(product.can_be_subscribed?).to be false
        end

        it 'returns true when in stock' do
          product.update!(stock_quantity: 5)
          # Update variant stock as well since the product has a default variant
          product.product_variants.first.update!(stock_quantity: 5) if product.has_variants?
          expect(product.can_be_subscribed?).to be true
        end
      end

      context 'when stock management is disabled' do
        before do
          business.update!(stock_management_enabled: false)
          product.reload
        end

        it 'returns true even when stock is 0' do
          product.update!(stock_quantity: 0)
          expect(product.can_be_subscribed?).to be true
        end
      end
    end
  end
end 