require 'rails_helper'

RSpec.describe PromotionService, type: :model do
  let(:business) { create(:business) }
  let(:promotion) { create(:promotion, business: business) }
  let(:service) { create(:service, business: business) }

  describe 'associations' do
    it { should belong_to(:promotion) }
    it { should belong_to(:service) }
  end

  describe 'validations' do
    subject { create(:promotion_service, promotion: promotion, service: service) }
    
    it { should validate_uniqueness_of(:promotion_id).scoped_to(:service_id) }
  end

  describe 'factory' do
    it 'creates a valid promotion_service' do
      promotion_service = create(:promotion_service, promotion: promotion, service: service)
      expect(promotion_service).to be_valid
      expect(promotion_service.promotion).to eq(promotion)
      expect(promotion_service.service).to eq(service)
    end
  end

  describe 'uniqueness constraint' do
    it 'prevents duplicate promotion-service combinations' do
      create(:promotion_service, promotion: promotion, service: service)
      
      duplicate = build(:promotion_service, promotion: promotion, service: service)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:promotion_id]).to include('has already been taken')
    end

    it 'allows same promotion with different services' do
      service2 = create(:service, business: business)
      
      create(:promotion_service, promotion: promotion, service: service)
      
      promotion_service2 = build(:promotion_service, promotion: promotion, service: service2)
      expect(promotion_service2).to be_valid
    end

    it 'allows same service with different promotions' do
      promotion2 = create(:promotion, :code_based, business: business, code: 'DIFFERENT')
      
      create(:promotion_service, promotion: promotion, service: service)
      
      promotion_service2 = build(:promotion_service, promotion: promotion2, service: service)
      expect(promotion_service2).to be_valid
    end
  end
end
