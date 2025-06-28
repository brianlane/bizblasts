require 'rails_helper'

RSpec.describe Business, type: :model do
  describe 'stock management functionality' do
    let(:business) { create(:business) }

    describe '#stock_management_enabled?' do
      it 'returns true by default' do
        expect(business.stock_management_enabled?).to be true
      end

      it 'returns the value of stock_management_enabled attribute' do
        business.update!(stock_management_enabled: false)
        expect(business.stock_management_enabled?).to be false
      end
    end

    describe '#stock_management_disabled?' do
      it 'returns false by default' do
        expect(business.stock_management_disabled?).to be false
      end

      it 'returns true when stock management is disabled' do
        business.update!(stock_management_enabled: false)
        expect(business.stock_management_disabled?).to be true
      end
    end

    describe '#requires_stock_tracking?' do
      it 'returns true when stock management is enabled' do
        business.update!(stock_management_enabled: true)
        expect(business.requires_stock_tracking?).to be true
      end

      it 'returns false when stock management is disabled' do
        business.update!(stock_management_enabled: false)
        expect(business.requires_stock_tracking?).to be false
      end
    end

    describe 'default value' do
      it 'sets stock_management_enabled to true by default' do
        new_business = create(:business)
        expect(new_business.reload.stock_management_enabled).to be true
      end
    end

    describe 'ransackable attributes' do
      it 'includes stock_management_enabled in ransackable attributes' do
        expect(Business.ransackable_attributes).to include('stock_management_enabled')
      end
    end
  end
end 