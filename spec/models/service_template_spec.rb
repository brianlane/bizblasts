require 'rails_helper'

RSpec.describe ServiceTemplate, type: :model do
  describe '.ransackable_attributes' do
    it 'returns an array of searchable attribute names' do
      attributes = ServiceTemplate.ransackable_attributes
      expect(attributes).to be_an(Array)
      expect(attributes).to include('name')
      expect(attributes).to include('category')
      expect(attributes).to include('status')
      expect(attributes).to include('active')
      expect(attributes).to include('created_at')
    end
  end

  describe 'validations and defaults' do
    it 'is valid with valid attributes' do
      template = ServiceTemplate.new(name: "Test Template")
      expect(template).to be_valid
    end

    it 'defaults active to true' do
      template = ServiceTemplate.new(name: "Test Template")
      expect(template.active).to be true
    end

    it 'defaults status to draft' do
      template = ServiceTemplate.new(name: "Test Template")
      expect(template.status).to eq('draft')
    end

    it 'is invalid without a name' do
      template = ServiceTemplate.new(name: nil)
      expect(template).not_to be_valid
      expect(template.errors[:name]).to include("can't be blank")
    end
  end
end 