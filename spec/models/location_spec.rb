require 'rails_helper'

RSpec.describe Location, type: :model do
  let(:business) { create(:business) }

  it { should belong_to(:business) }
  it { should validate_presence_of(:name) }
  it { should validate_presence_of(:address) }
  it { should validate_presence_of(:city) }
  it { should validate_presence_of(:state) }
  it { should validate_presence_of(:zip) }
  it { should validate_presence_of(:hours) }

  describe 'hours JSON parsing' do
    it 'parses hours from a valid JSON string' do
      location = build(:location, hours: '{"mon":{"open":"09:00","close":"17:00"}}')
      expect(location.valid?).to be true
      expect(location.hours).to eq({ 'mon' => { 'open' => '09:00', 'close' => '17:00' } })
    end

    it 'sets hours to empty hash if invalid JSON' do
      location = build(:location, hours: '{invalid_json}')
      expect(location.valid?).to be false # because hours is required, but will be set to {}
      expect(location.hours).to eq({})
    end

    it 'keeps hours as hash if already a hash' do
      hours_hash = { 'mon' => { 'open' => '09:00', 'close' => '17:00' } }
      location = build(:location, hours: hours_hash)
      expect(location.valid?).to be true
      expect(location.hours).to eq(hours_hash)
    end
  end

  describe '#display_hours' do
    it 'returns JSON string if hours is a hash' do
      location = build(:location)
      expect(location.display_hours).to eq(location.hours.to_json)
    end
    it 'returns hours as is if already a string' do
      location = build(:location, hours: '{"mon":{"open":"09:00","close":"17:00"}}')
      expect(location.display_hours).to eq('{"mon":{"open":"09:00","close":"17:00"}}')
    end
  end
end 