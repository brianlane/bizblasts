# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DocumentSignature, type: :model do
  let(:business) { create(:business) }
  let(:other_business) { create(:business) }
  let(:customer) { create(:tenant_customer, business: business) }
  let(:client_document) { create(:client_document, business: business, tenant_customer: customer) }

  describe 'validations' do
    it 'defaults role to client' do
      signature = DocumentSignature.new(client_document: client_document, signer_name: 'Test')
      expect(signature.role).to eq('client')
      expect(signature).to be_valid
    end

    it 'requires signer_name' do
      signature = DocumentSignature.new(client_document: client_document, role: 'client')
      expect(signature).not_to be_valid
      expect(signature.errors[:signer_name]).to include("can't be blank")
    end

    it 'sets business_id from client_document automatically' do
      signature = DocumentSignature.new(
        client_document: client_document,
        role: 'client',
        signer_name: 'John Doe'
      )
      signature.valid?
      expect(signature.business_id).to eq(business.id)
    end

    it 'prevents mismatched business_id' do
      signature = DocumentSignature.new(
        client_document: client_document,
        business: other_business,
        role: 'client',
        signer_name: 'John Doe'
      )
      expect(signature).not_to be_valid
      expect(signature.errors[:business]).to include("must match the client document's business")
    end

    it 'allows matching business_id' do
      signature = DocumentSignature.new(
        client_document: client_document,
        business: business,
        role: 'client',
        signer_name: 'John Doe'
      )
      expect(signature).to be_valid
    end
  end

  describe 'callbacks' do
    it 'sets signed_at when signature_data is present' do
      freeze_time do
        signature = DocumentSignature.create!(
          client_document: client_document,
          role: 'client',
          signer_name: 'John Doe',
          signature_data: 'data:image/png;base64,AAAA'
        )
        expect(signature.signed_at).to eq(Time.current)
      end
    end

    it 'does not set signed_at when signature_data is blank' do
      signature = DocumentSignature.create!(
        client_document: client_document,
        role: 'client',
        signer_name: 'John Doe'
      )
      expect(signature.signed_at).to be_nil
    end
  end
end
