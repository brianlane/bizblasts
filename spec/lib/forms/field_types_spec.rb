require 'rails_helper'

RSpec.describe Forms::FieldTypes do
  describe '.all' do
    it 'returns a hash of field types' do
      expect(described_class.all).to be_a(Hash)
      expect(described_class.all).not_to be_empty
      expect(described_class.all[:text]).to eq('Text')
      expect(described_class.all[:number]).to eq('Number')
    end
  end

  describe '.valid_type?' do
    it 'returns true for valid type symbols' do
      expect(described_class.valid_type?(:text)).to be true
      expect(described_class.valid_type?(:select)).to be true
    end

    it 'returns true for valid type strings' do
      expect(described_class.valid_type?('text')).to be true
      expect(described_class.valid_type?('select')).to be true
    end

    it 'returns false for invalid types' do
      expect(described_class.valid_type?(:unknown)).to be false
      expect(described_class.valid_type?('invalid')).to be false
      expect(described_class.valid_type?(nil)).to be false # Test nil case
      expect(described_class.valid_type?(123)).to be false   # Test non-string/symbol
    end
  end
end 