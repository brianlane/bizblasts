require 'rails_helper'

RSpec.describe Sms::MessageTemplates do
  describe '.reminder_template' do
    it 'returns the reminder message template string' do
      expect(described_class.reminder_template).to be_a(String)
      expect(described_class.reminder_template).to include("%DATE%")
      expect(described_class.reminder_template).to include("%TIME%")
      expect(described_class.reminder_template).to include("%BUSINESS_NAME%")
    end
  end

  describe '.confirmation_template' do
    it 'returns the confirmation message template string' do
      expect(described_class.confirmation_template).to be_a(String)
      expect(described_class.confirmation_template).to include("%SERVICE_NAME%")
      expect(described_class.confirmation_template).to include("%DATE%")
      expect(described_class.confirmation_template).to include("%TIME%")
    end
  end

  describe '.cancellation_template' do
    it 'returns the cancellation message template string' do
      expect(described_class.cancellation_template).to be_a(String)
      expect(described_class.cancellation_template).to include("%DATE%")
      expect(described_class.cancellation_template).to include("%TIME%")
    end
  end

  describe '.update_template' do
    it 'returns the update message template string' do
      expect(described_class.update_template).to be_a(String)
      expect(described_class.update_template).to include("%DATE%")
      expect(described_class.update_template).to include("%TIME%")
    end
  end
end 