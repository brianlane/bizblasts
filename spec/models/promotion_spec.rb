require 'rails_helper'

RSpec.describe Promotion, type: :model do
  let(:business) { create(:business) }
  let(:product) { create(:product, business: business, price: 100.0) }
  let(:service) { create(:service, business: business, price: 150.0) }
  
  before do
    ActsAsTenant.current_tenant = business
  end

  describe 'promotional pricing' do
    context 'with percentage discount' do
      let(:promotion) do
        create(:promotion, :automatic,
               business: business,
               discount_type: 'percentage',
               discount_value: 20.0,
               start_date: 1.week.ago,
               end_date: 1.week.from_now,
               active: true,
               applicable_to_products: true)
      end

      before do
        promotion.promotion_products.create!(product: product)
      end

      it 'calculates promotional price correctly' do
        expect(promotion.calculate_promotional_price(100.0)).to eq(80.0)
      end

      it 'calculates discount amount correctly' do
        expect(promotion.calculate_discount(100.0)).to eq(20.0)
      end

      it 'provides correct display text' do
        expect(promotion.display_text).to eq('20% OFF')
      end

      it 'identifies active promotion for product' do
        expect(Promotion.active_promotion_for_product(product)).to eq(promotion)
      end

      it 'product shows promotional pricing' do
        expect(product.on_promotion?).to be true
        expect(product.promotional_price).to eq(80.0)
        expect(product.promotion_discount_amount).to eq(20.0)
        expect(product.savings_percentage).to eq(20)
        expect(product.promotion_display_text).to eq('20% OFF')
      end
    end

    context 'with fixed amount discount' do
      let(:promotion) do
        create(:promotion, :automatic,
               business: business,
               discount_type: 'fixed_amount',
               discount_value: 25.0,
               start_date: 1.week.ago,
               end_date: 1.week.from_now,
               active: true,
               applicable_to_services: true)
      end

      before do
        promotion.promotion_services.create!(service: service)
      end

      it 'calculates promotional price correctly' do
        expect(promotion.calculate_promotional_price(150.0)).to eq(125.0)
      end

      it 'calculates discount amount correctly' do
        expect(promotion.calculate_discount(150.0)).to eq(25.0)
      end

      it 'provides correct display text' do
        expect(promotion.display_text).to eq('$25.0 OFF')
      end

      it 'service shows promotional pricing' do
        expect(service.on_promotion?).to be true
        expect(service.promotional_price).to eq(125.0)
        expect(service.promotion_discount_amount).to eq(25.0)
        expect(service.savings_percentage).to eq(17) # 25/150 * 100 rounded
        expect(service.promotion_display_text).to eq('$25.0 OFF')
      end
    end

    context 'with inactive promotion' do
      let(:promotion) do
        create(:promotion, :automatic,
               business: business,
               discount_type: 'percentage',
               discount_value: 20.0,
               start_date: 1.week.ago,
               end_date: 1.week.from_now,
               active: false,
               applicable_to_products: true)
      end

      before do
        promotion.promotion_products.create!(product: product)
      end

      it 'does not apply promotional pricing' do
        expect(product.on_promotion?).to be false
        expect(product.promotional_price).to eq(100.0)
        expect(product.promotion_discount_amount).to eq(0)
      end
    end

    context 'with expired promotion' do
      let(:promotion) do
        create(:promotion, :automatic,
               business: business,
               discount_type: 'percentage',
               discount_value: 20.0,
               start_date: 2.weeks.ago,
               end_date: 1.week.ago,
               active: true,
               applicable_to_products: true)
      end

      before do
        promotion.promotion_products.create!(product: product)
      end

      it 'does not apply promotional pricing' do
        expect(product.on_promotion?).to be false
        expect(product.promotional_price).to eq(100.0)
      end
    end

    context 'with usage limit reached' do
      let(:promotion) do
        create(:promotion, :automatic,
               business: business,
               discount_type: 'percentage',
               discount_value: 20.0,
               start_date: 1.week.ago,
               end_date: 1.week.from_now,
               active: true,
               usage_limit: 5,
               current_usage: 5,
               applicable_to_products: true)
      end

      before do
        promotion.promotion_products.create!(product: product)
      end

      it 'does not apply promotional pricing' do
        expect(product.on_promotion?).to be false
        expect(product.promotional_price).to eq(100.0)
      end
    end
  end
end 