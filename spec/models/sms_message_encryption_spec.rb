# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SmsMessage, type: :model do
  describe 'phone number encryption' do
    let(:business) { create(:business) }
    let(:tenant_customer) { create(:tenant_customer, business: business) }
    let(:plain_phone) { '+15551234567' }
    
    it 'encrypts phone_number using Rails ActiveRecord::Encryption' do
      sms = create(:sms_message, 
                   phone_number: plain_phone,
                   business: business,
                   tenant_customer: tenant_customer)
      
      # Verify that encryption is configured for this attribute
      expect(SmsMessage.encrypted_attributes).to include(:phone_number)
    end
    
    it 'stores encrypted JSON in the phone_number column (Rails 8.0 convention)' do
      sms = create(:sms_message,
                   phone_number: plain_phone,
                   business: business,
                   tenant_customer: tenant_customer)
      
      # Raw column value should be encrypted JSON, not plaintext
      raw_value = sms.read_attribute_before_type_cast(:phone_number)
      
      # Verify it's encrypted (JSON string with Rails encryption structure)
      expect(raw_value).to be_a(String)
      parsed = JSON.parse(raw_value)
      expect(parsed).to have_key('p')  # Payload
      expect(parsed).to have_key('h')  # Headers (iv, at)
      expect(parsed['h']).to have_key('iv')  # Initialization vector
      expect(parsed['h']).to have_key('at')  # Authentication tag
      
      # Verify plaintext is NOT stored
      expect(raw_value).not_to include(plain_phone)
      expect(raw_value).not_to eq(plain_phone)
    end
    
    it 'automatically decrypts phone_number when accessed' do
      sms = create(:sms_message,
                   phone_number: plain_phone,
                   business: business,
                   tenant_customer: tenant_customer)
      
      # Reading the attribute returns decrypted plaintext
      expect(sms.phone_number).to eq(plain_phone)
      
      # But raw value is different (encrypted)
      expect(sms.phone_number).not_to eq(sms.read_attribute_before_type_cast(:phone_number))
    end
    
    it 'uses phone_number column (not phone_number_ciphertext) per Rails 8.0 convention' do
      columns = ActiveRecord::Base.connection.columns(:sms_messages)
      phone_columns = columns.select { |c| c.name.include?('phone') }.map(&:name)
      
      # Rails 8.0 stores encrypted data in the same column name as the attribute
      expect(phone_columns).to include('phone_number')
      expect(phone_columns).not_to include('phone_number_ciphertext')
    end
    
    it 'allows deterministic querying with encrypted values' do
      sms1 = create(:sms_message,
                    phone_number: plain_phone,
                    business: business,
                    tenant_customer: tenant_customer)
      
      # for_phone scope should find the record using deterministic encryption
      found = SmsMessage.for_phone(plain_phone)
      expect(found).to include(sms1)
    end
  end
end

