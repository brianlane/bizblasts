require 'rails_helper'

RSpec.describe TipConfiguration, type: :model do
  let(:business) { create(:business) }
  let(:tip_configuration) { create(:tip_configuration, business: business) }

  describe 'associations' do
    it { should belong_to(:business).required }
  end

  describe 'validations' do
    it { should validate_presence_of(:default_tip_percentages) }
    it { should validate_inclusion_of(:custom_tip_enabled).in_array([true, false]) }
    
    it 'validates uniqueness of business_id' do
      # Create an existing tip configuration
      existing_config = create(:tip_configuration, business: business)
      
      # Try to create another one for the same business
      duplicate_config = build(:tip_configuration, business: business)
      
      expect(duplicate_config).not_to be_valid
      expect(duplicate_config.errors[:business_id]).to include('has already been taken')
    end
  end

  describe 'scopes and ransack' do
    it 'has ransackable attributes' do
      expected_attributes = %w[id business_id default_tip_percentages custom_tip_enabled tip_message created_at updated_at]
      expect(TipConfiguration.ransackable_attributes).to match_array(expected_attributes)
    end

    it 'has ransackable associations' do
      expected_associations = %w[business]
      expect(TipConfiguration.ransackable_associations).to match_array(expected_associations)
    end
  end

  describe '#tip_percentage_options' do
    context 'when default_tip_percentages is set' do
      it 'returns the configured percentages' do
        tip_configuration.default_tip_percentages = [10, 15, 20]
        expect(tip_configuration.tip_percentage_options).to eq([10, 15, 20])
      end
    end

    context 'when default_tip_percentages is nil' do
      it 'returns default percentages' do
        tip_configuration.default_tip_percentages = nil
        expect(tip_configuration.tip_percentage_options).to eq([15, 18, 20])
      end
    end
  end

  describe '#calculate_tip_amounts' do
    let(:base_amount) { 100.00 }

    it 'calculates tip amounts for each percentage' do
      tip_configuration.default_tip_percentages = [15, 18, 20]
      
      result = tip_configuration.calculate_tip_amounts(base_amount)
      
      expect(result).to eq([
        { percentage: 15, amount: 15.00 },
        { percentage: 18, amount: 18.00 },
        { percentage: 20, amount: 20.00 }
      ])
    end

    it 'rounds amounts to 2 decimal places' do
      tip_configuration.default_tip_percentages = [16.67]
      
      result = tip_configuration.calculate_tip_amounts(base_amount)
      
      expect(result.first[:amount]).to eq(16.67)
    end

    context 'with different base amounts' do
      it 'calculates correctly for small amounts' do
        tip_configuration.default_tip_percentages = [20]
        
        result = tip_configuration.calculate_tip_amounts(5.00)
        
        expect(result.first[:amount]).to eq(1.00)
      end

      it 'calculates correctly for large amounts' do
        tip_configuration.default_tip_percentages = [15]
        
        result = tip_configuration.calculate_tip_amounts(1000.00)
        
        expect(result.first[:amount]).to eq(150.00)
      end
    end
  end

  describe 'factory' do
    it 'creates a valid tip configuration' do
      expect(tip_configuration).to be_valid
    end

    it 'has default values' do
      expect(tip_configuration.default_tip_percentages).to eq([15, 18, 20])
      expect(tip_configuration.custom_tip_enabled).to be true
      expect(tip_configuration.tip_message).to be_present
    end
  end

  describe 'traits' do
    it 'creates custom_disabled configuration' do
      config = create(:tip_configuration, :custom_disabled)
      expect(config.custom_tip_enabled).to be false
    end

    it 'creates high_percentages configuration' do
      config = create(:tip_configuration, :high_percentages)
      expect(config.default_tip_percentages).to eq([20, 25, 30])
    end

    it 'creates low_percentages configuration' do
      config = create(:tip_configuration, :low_percentages)
      expect(config.default_tip_percentages).to eq([10, 12, 15])
    end

    it 'creates no_message configuration' do
      config = create(:tip_configuration, :no_message)
      expect(config.tip_message).to be_nil
    end

    it 'creates with_custom_message configuration' do
      config = create(:tip_configuration, :with_custom_message)
      expect(config.tip_message).to eq("Your generosity helps our team provide exceptional service!")
    end
  end
end 