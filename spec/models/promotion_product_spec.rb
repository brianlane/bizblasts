require 'rails_helper'

RSpec.describe PromotionProduct, type: :model do
  let(:business) { create(:business) }
  let(:promotion) { create(:promotion, business: business) }
  let(:product) { create(:product, business: business) }

  describe 'associations' do
    it { should belong_to(:promotion) }
    it { should belong_to(:product) }
  end

  describe 'validations' do
    subject { create(:promotion_product, promotion: promotion, product: product) }
    
    it { should validate_uniqueness_of(:promotion_id).scoped_to(:product_id) }
  end

  describe 'factory' do
    it 'creates a valid promotion_product' do
      promotion_product = create(:promotion_product, promotion: promotion, product: product)
      expect(promotion_product).to be_valid
      expect(promotion_product.promotion).to eq(promotion)
      expect(promotion_product.product).to eq(product)
    end
  end

  describe 'uniqueness constraint' do
    it 'prevents duplicate promotion-product combinations' do
      create(:promotion_product, promotion: promotion, product: product)
      
      duplicate = build(:promotion_product, promotion: promotion, product: product)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:promotion_id]).to include('has already been taken')
    end

    it 'allows same promotion with different products' do
      product2 = create(:product, business: business)
      
      create(:promotion_product, promotion: promotion, product: product)
      
      promotion_product2 = build(:promotion_product, promotion: promotion, product: product2)
      expect(promotion_product2).to be_valid
    end

    it 'allows same product with different promotions' do
      promotion2 = create(:promotion, :code_based, business: business, code: 'DIFFERENT')
      
      create(:promotion_product, promotion: promotion, product: product)
      
      promotion_product2 = build(:promotion_product, promotion: promotion2, product: product)
      expect(promotion_product2).to be_valid
    end
  end
end
