require 'rails_helper'

RSpec.describe StockMovement, type: :model do
  let(:business) { create(:business) }
  let(:product) { create(:product, business: business) }

  describe 'validations' do
    it 'requires product' do
      stock_movement = build(:stock_movement, product: nil)
      expect(stock_movement).not_to be_valid
      expect(stock_movement.errors[:product]).to include("can't be blank")
    end

    it 'requires quantity' do
      stock_movement = build(:stock_movement, quantity: nil)
      expect(stock_movement).not_to be_valid
      expect(stock_movement.errors[:quantity]).to include("can't be blank")
    end

    it 'requires movement_type' do
      stock_movement = build(:stock_movement, movement_type: nil)
      expect(stock_movement).not_to be_valid
      expect(stock_movement.errors[:movement_type]).to include("can't be blank")
    end

    it 'validates quantity is not zero' do
      stock_movement = build(:stock_movement, quantity: 0)
      expect(stock_movement).not_to be_valid
      expect(stock_movement.errors[:quantity]).to include("must be other than 0")
    end

    it 'validates movement_type inclusion' do
      stock_movement = build(:stock_movement, movement_type: 'invalid_type')
      expect(stock_movement).not_to be_valid
      expect(stock_movement.errors[:movement_type]).to include("is not included in the list")
    end

    it 'allows valid movement types' do
      %w[subscription_fulfillment restock adjustment return].each do |type|
        stock_movement = build(:stock_movement, movement_type: type)
        expect(stock_movement).to be_valid
      end
    end
  end

  describe 'associations' do
    it 'belongs to product' do
      association = described_class.reflect_on_association(:product)
      expect(association.macro).to eq(:belongs_to)
    end
  end

  describe 'scopes' do
    let!(:inbound_movement) { create(:stock_movement, product: product, quantity: 10) }
    let!(:outbound_movement) { create(:stock_movement, product: product, quantity: -5) }
    let!(:restock_movement) { create(:stock_movement, product: product, quantity: 20, movement_type: 'restock') }

    describe '.inbound' do
      it 'returns movements with positive quantity' do
        expect(StockMovement.inbound).to include(inbound_movement, restock_movement)
        expect(StockMovement.inbound).not_to include(outbound_movement)
      end
    end

    describe '.outbound' do
      it 'returns movements with negative quantity' do
        expect(StockMovement.outbound).to include(outbound_movement)
        expect(StockMovement.outbound).not_to include(inbound_movement, restock_movement)
      end
    end

    describe '.by_type' do
      it 'returns movements of specified type' do
        expect(StockMovement.by_type('restock')).to include(restock_movement)
        expect(StockMovement.by_type('restock')).not_to include(inbound_movement, outbound_movement)
      end
    end
  end

  describe 'instance methods' do
    describe '#inbound?' do
      it 'returns true for positive quantities' do
        movement = build(:stock_movement, quantity: 10)
        expect(movement.inbound?).to be true
      end

      it 'returns false for negative quantities' do
        movement = build(:stock_movement, quantity: -5)
        expect(movement.inbound?).to be false
      end
    end

    describe '#outbound?' do
      it 'returns true for negative quantities' do
        movement = build(:stock_movement, quantity: -5)
        expect(movement.outbound?).to be true
      end

      it 'returns false for positive quantities' do
        movement = build(:stock_movement, quantity: 10)
        expect(movement.outbound?).to be false
      end
    end
  end
end
