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

  describe 'date handling' do
    context 'when start_date is blank' do
      it 'sets start_date to current time before validation' do
        promotion = build(:promotion, start_date: nil)
        expect(promotion.valid?).to be true
        expect(promotion.start_date).to be_within(1.second).of(Time.current)
      end
    end

    context 'when end_date is blank' do
      it 'leaves end_date as nil (never expires)' do
        promotion = create(:promotion, end_date: nil)
        expect(promotion.end_date).to be_nil
        expect(promotion.currently_active?).to be true
      end
    end

    context 'when both dates are blank' do
      it 'sets start_date to now and leaves end_date as nil' do
        promotion = build(:promotion, start_date: nil, end_date: nil)
        expect(promotion.valid?).to be true
        expect(promotion.start_date).to be_within(1.second).of(Time.current)
        expect(promotion.end_date).to be_nil
      end
    end

    context 'date validation' do
      it 'validates end_date is after start_date when both are present' do
        promotion = build(:promotion, 
                         start_date: 1.day.from_now, 
                         end_date: Time.current)
        expect(promotion.valid?).to be false
        expect(promotion.errors[:end_date]).to include('must be after the start date')
      end

      it 'does not validate dates when end_date is nil' do
        promotion = build(:promotion, 
                         start_date: 1.day.from_now, 
                         end_date: nil)
        expect(promotion.valid?).to be true
      end
    end
  end

  describe 'scopes with nil end_date' do
    let!(:never_expires) { create(:promotion, :never_expires, active: true) }
    let!(:expires_future) { create(:promotion, active: true, start_date: 1.week.ago, end_date: 1.week.from_now) }
    let!(:expired) { create(:promotion, active: true, start_date: 2.weeks.ago, end_date: 1.week.ago) }

    describe '.active' do
      it 'includes promotions that never expire' do
        expect(Promotion.active).to include(never_expires)
        expect(Promotion.active).to include(expires_future)
        expect(Promotion.active).not_to include(expired)
      end
    end

    describe '.expired' do
      it 'does not include promotions that never expire' do
        expect(Promotion.expired).not_to include(never_expires)
        expect(Promotion.expired).to include(expired)
      end
    end
  end
end 