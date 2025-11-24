# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ServiceVariant, type: :model do
  let(:business) { create(:business) }
  let(:service)  { create(:service, business: business) }

  it 'is valid with valid attributes' do
    variant = described_class.new(service: service, name: '30 min', duration: 30, price: 49.99)
    expect(variant).to be_valid
  end

  it 'requires a name' do
    variant = described_class.new(service: service, name: nil, duration: 30, price: 49.99)
    expect(variant).not_to be_valid
  end

  it 'requires positive duration' do
    variant = described_class.new(service: service, name: 'Bad', duration: 0, price: 10)
    expect(variant).not_to be_valid
  end

  context 'price validation' do
    it 'rejects invalid price formats with custom error message' do
      variant = described_class.new(service: service, name: 'Test', duration: 30, price: 'abcd')
      expect(variant).not_to be_valid
      expect(variant.errors[:price]).to include("must be a valid number - 'abcd' is not a valid price format (e.g., '10.50' or '$10.50')")
    end

    it 'rejects nil price' do
      variant = described_class.new(service: service, name: 'Test', duration: 30, price: nil)
      expect(variant).not_to be_valid
      expect(variant.errors[:price]).to include("can't be blank")
    end

    it 'rejects empty string price' do
      variant = described_class.new(service: service, name: 'Test', duration: 30, price: '')
      expect(variant).not_to be_valid
      expect(variant.errors[:price]).to include("can't be blank")
    end

    it 'accepts valid numeric price' do
      variant = described_class.new(service: service, name: 'Test', duration: 30, price: '10.50')
      variant.valid?
      expect(variant.errors[:price]).to be_empty
    end

    it 'accepts valid currency formatted price' do
      variant = described_class.new(service: service, name: 'Test', duration: 30, price: '$10.50')
      variant.valid?
      expect(variant.errors[:price]).to be_empty
    end
  end

  it 'delegates business to service' do
    variant = described_class.create!(service: service, name: '30 min', duration: 30, price: 49.99)
    expect(variant.business).to eq(business)
  end

  describe 'uniqueness validation' do
    it 'allows variants with same name but different durations' do
      create(:service_variant, service: service, name: 'Reiki', duration: 60, price: 130)
      variant = build(:service_variant, service: service, name: 'Reiki', duration: 75, price: 150)
      expect(variant).to be_valid
    end

    it 'prevents variants with same name and duration' do
      create(:service_variant, service: service, name: 'Reiki', duration: 60, price: 130)
      variant = build(:service_variant, service: service, name: 'Reiki', duration: 60, price: 150)
      expect(variant).not_to be_valid
      expect(variant.errors[:name]).to include('must be unique for each duration within a service')
    end

    it 'allows same name and duration across different services' do
      other_service = create(:service, business: business)
      create(:service_variant, service: service, name: 'Reiki', duration: 60, price: 130)
      variant = build(:service_variant, service: other_service, name: 'Reiki', duration: 60, price: 130)
      expect(variant).to be_valid
    end
  end
end 