# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DocumentTemplate, type: :model do
  let(:business) { create(:business) }

  before do
    ActsAsTenant.current_tenant = business
  end

  describe 'validations' do
    subject { build(:document_template, business: business) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:document_type) }
    it { is_expected.to validate_presence_of(:body) }
    it { is_expected.to validate_inclusion_of(:document_type).in_array(DocumentTemplate::DOCUMENT_TYPES.map(&:last)) }
  end

  describe 'associations' do
    it { is_expected.to belong_to(:business).without_validating_presence }
    it { is_expected.to have_many(:services).dependent(:nullify) }
    it { is_expected.to have_many(:products).dependent(:nullify) }
    it { is_expected.to have_many(:client_documents).dependent(:nullify) }
  end

  describe 'DOCUMENT_TYPES' do
    it 'includes estimate type' do
      expect(DocumentTemplate::DOCUMENT_TYPES).to include(['Estimate approval', 'estimate'])
    end

    it 'includes rental_security_deposit type' do
      expect(DocumentTemplate::DOCUMENT_TYPES).to include(['Rental security deposit', 'rental_security_deposit'])
    end

    it 'includes experience_booking type' do
      expect(DocumentTemplate::DOCUMENT_TYPES).to include(['Experience booking', 'experience_booking'])
    end

    it 'includes service type' do
      expect(DocumentTemplate::DOCUMENT_TYPES).to include(['Service agreement', 'service'])
    end

    it 'includes product type' do
      expect(DocumentTemplate::DOCUMENT_TYPES).to include(['Product agreement', 'product'])
    end

    it 'includes standalone type' do
      expect(DocumentTemplate::DOCUMENT_TYPES).to include(['Standalone document', 'standalone'])
    end
  end

  describe 'versioning' do
    it 'auto-increments version for same document type' do
      template1 = create(:document_template, business: business, document_type: 'estimate')
      template2 = create(:document_template, business: business, document_type: 'estimate')

      expect(template1.version).to eq(1)
      expect(template2.version).to eq(2)
    end

    it 'starts at version 1 for different document types' do
      template1 = create(:document_template, business: business, document_type: 'estimate')
      template2 = create(:document_template, business: business, document_type: 'service')

      expect(template1.version).to eq(1)
      expect(template2.version).to eq(1)
    end
  end

  describe 'scopes' do
    let!(:active_template) { create(:document_template, business: business, active: true) }
    let!(:inactive_template) { create(:document_template, business: business, active: false) }

    describe '.active' do
      it 'returns only active templates' do
        expect(described_class.active).to include(active_template)
        expect(described_class.active).not_to include(inactive_template)
      end
    end

    describe '.for_type' do
      let!(:estimate_template) { create(:document_template, business: business, document_type: 'estimate') }
      let!(:service_template) { create(:document_template, business: business, document_type: 'service') }

      it 'returns templates of the specified type' do
        expect(described_class.for_type('estimate')).to include(estimate_template)
        expect(described_class.for_type('estimate')).not_to include(service_template)
      end
    end
  end
end

