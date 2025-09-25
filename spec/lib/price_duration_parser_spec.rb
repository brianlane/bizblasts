require 'rails_helper'

# Test model to verify PriceDurationParser functionality
class TestPriceDurationModel
  include ActiveModel::Model
  include ActiveModel::Attributes
  include ActiveModel::Validations
  include PriceDurationParser
  
  attribute :price, :decimal
  attribute :duration, :integer
  
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :duration, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validate :price_format_valid
  
  price_parser :price
  duration_parser :duration
end

RSpec.describe PriceDurationParser do
  let(:model) { TestPriceDurationModel.new }
  
  describe 'price parsing' do
    context 'valid prices' do
      it 'parses simple decimal prices' do
        model.price = '10.50'
        expect(model.price).to eq(10.50)
      end
      
      it 'parses prices with dollar sign' do
        model.price = '$25.99'
        expect(model.price).to eq(25.99)
      end
      
      it 'parses whole number prices' do
        model.price = '15'
        expect(model.price).to eq(15.00)
      end
      
      it 'handles prices with spaces' do
        model.price = '  $12.34  '
        expect(model.price).to eq(12.34)
      end
      
      it 'rounds to 2 decimal places' do
        model.price = '10.999'
        expect(model.price).to eq(11.00)
      end
    end
    
    context 'invalid prices' do
      it 'sets to nil for non-numeric strings' do
        model.price = 'abc'
        expect(model.price).to be_nil
        expect(model).not_to be_valid
        expect(model.errors[:price]).to include("must be a valid number - 'abc' is not a valid price format (e.g., '10.50' or '$10.50')")
      end
      
      it 'sets to nil for negative prices' do
        model.price = '-10.50'
        expect(model.price).to be_nil
        expect(model).not_to be_valid
      end
      
      it 'sets to nil for blank strings' do
        model.price = '   '
        expect(model.price).to be_nil
        expect(model).not_to be_valid
        expect(model.errors[:price]).to include("can't be blank")
      end
      
      it 'handles mixed invalid characters' do
        model.price = '$10.50abc'
        expect(model.price).to be_nil
        expect(model).not_to be_valid
      end
    end
  end
  
  describe 'duration parsing' do
    context 'valid durations' do
      it 'parses simple numeric durations' do
        model.duration = '60'
        expect(model.duration).to eq(60)
      end
      
      it 'parses durations with units' do
        model.duration = '90 minutes'
        expect(model.duration).to eq(90)
      end
      
      it 'parses decimal durations and rounds' do
        model.duration = '45.7 min'
        expect(model.duration).to eq(46)
      end
      
      it 'extracts first numeric value' do
        model.duration = '30-45 minutes'
        expect(model.duration).to eq(30)
      end
    end
    
    context 'invalid durations' do
      it 'sets to nil for non-numeric strings' do
        model.duration = 'abc'
        expect(model.duration).to be_nil
        expect(model).not_to be_valid
      end
      
      it 'sets to nil for zero duration' do
        model.duration = '0 minutes'
        expect(model.duration).to be_nil
        expect(model).not_to be_valid
      end
    end
  end
  
  describe 'integration with validations' do
    it 'validates successfully with valid price and duration' do
      model.price = '$15.50'
      model.duration = '60 minutes'
      expect(model).to be_valid
    end
    
    it 'fails validation with invalid price' do
      model.price = 'invalid'
      model.duration = '60'
      expect(model).not_to be_valid
      expect(model.errors[:price]).to be_present
    end
    
    it 'fails validation with invalid duration' do
      model.price = '15.50'
      model.duration = 'invalid'
      expect(model).not_to be_valid
      expect(model.errors[:duration]).to be_present
    end
  end
end
