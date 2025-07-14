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

  it 'delegates business to service' do
    variant = described_class.create!(service: service, name: '30 min', duration: 30, price: 49.99)
    expect(variant.business).to eq(business)
  end
end 