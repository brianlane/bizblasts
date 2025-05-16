require 'rails_helper'

RSpec.describe NotificationTemplate, type: :model do
  let(:business) { create(:business) }

  it { should belong_to(:business) }
  it { should validate_presence_of(:event_type) }
  it { should validate_presence_of(:channel) }
  it { should validate_presence_of(:subject) }
  it { should validate_presence_of(:body) }

  describe 'enum channel' do
    it 'accepts valid values' do
      template = build(:notification_template, channel: :email)
      expect(template).to be_valid
      template = build(:notification_template, channel: :sms)
      expect(template).to be_valid
    end
    it 'rejects invalid values' do
      expect {
        build(:notification_template, channel: 'invalid')
      }.to raise_error(ArgumentError)
    end
  end
end 