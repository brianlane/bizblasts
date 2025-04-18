# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Service, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:business) }
    it { is_expected.to have_many(:bookings).dependent(:restrict_with_error) }
    it { is_expected.to have_many(:staff_assignments).dependent(:destroy) }
    it { is_expected.to have_many(:assigned_staff).through(:staff_assignments).source(:user) }
  end

  describe 'validations' do
    let(:business) { create(:business) }
    subject { build(:service, business: business) }
    
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:duration) }
    it { is_expected.to validate_presence_of(:price) }
    
    it 'validates uniqueness of name scoped to business_id' do
      create(:service, name: 'Test Service', business: business)
      duplicate = build(:service, name: 'Test Service', business: business)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to include('has already been taken')
    end
    
    it 'allows duplicate names across different businesses' do
      business1 = create(:business)
      business2 = create(:business)
      create(:service, name: 'Test Service', business: business1)
      service2 = build(:service, name: 'Test Service', business: business2)
      expect(service2).to be_valid
    end
  end

  describe 'scopes' do
    it '.active returns only active services' do
      business = create(:business)
      active_service = create(:service, active: true, business: business)
      inactive_service = create(:service, active: false, business: business)
      
      expect(Service.active).to include(active_service)
      expect(Service.active).not_to include(inactive_service)
    end
  end
end
