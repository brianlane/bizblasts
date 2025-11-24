require 'rails_helper'

RSpec.describe Sms::DeliveryProcessor do
  describe '.process_delivery' do
    let(:phone_number) { "1234567890" }
    let(:message) { "Test message" }

    it 'returns true when SmsService reports success' do
      allow(SmsService).to receive(:send_message).and_return({ success: true })
      expect(described_class.process_delivery(phone_number, message)).to be true
    end

    # TODO: Add tests for actual SMS delivery integration (e.g., mocking API calls)
  end

  describe '.validate_phone_number' do
    it 'returns true for valid phone numbers' do
      expect(described_class.validate_phone_number("1234567890")).to be true
      expect(described_class.validate_phone_number("123-456-7890")).to be true
      expect(described_class.validate_phone_number("(123) 456-7890")).to be true
    end

    it 'returns false for invalid phone numbers' do
      expect(described_class.validate_phone_number("12345")).to be false
      expect(described_class.validate_phone_number("")).to be false
      expect(described_class.validate_phone_number(nil)).to be false
    end
  end

  describe '.delivery_status' do
    let(:delivery_id) { "some_delivery_id" }

    it 'returns the status symbol from the corresponding SmsMessage' do
      sms_double = instance_double(SmsMessage, status: 'delivered')
      allow(SmsMessage).to receive(:find_by).with(external_id: delivery_id).and_return(sms_double)
      expect(described_class.delivery_status(delivery_id)).to eq(:delivered)
    end

    # TODO: Add tests for checking actual delivery status from provider
  end
end 