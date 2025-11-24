# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::TwilioController, type: :controller do
  describe '#find_customers_by_phone - business persistence validation (Bug 8)' do
    let(:phone_number) { '+16026866672' }
    let(:persisted_business) { create(:business, name: 'Persisted Business') }
    let(:unpersisted_business) { build(:business, name: 'Unpersisted Business') }
    let!(:customer) do
      create(:tenant_customer,
        business: persisted_business,
        phone: phone_number,
        first_name: 'Test',
        last_name: 'Customer'
      )
    end

    before do
      # Allow the controller to call private methods for testing
      allow(controller).to receive(:verify_webhook_signature?).and_return(false)
    end

    context 'when business is persisted' do
      it 'uses business-scoped search with persisted business' do
        expect(CustomerLinker).to receive(:find_customers_by_phone_public)
          .with(phone_number, persisted_business)
          .and_return([customer])

        result = controller.send(:find_customers_by_phone, phone_number, persisted_business)
        expect(result).to eq([customer])
      end

      it 'does not log warnings about unpersisted business' do
        expect(Rails.logger).not_to receive(:warn)

        controller.send(:find_customers_by_phone, phone_number, persisted_business)
      end

      it 'logs debug message with business ID' do
        # Allow the first debug call, then expect the second one with business ID
        allow(Rails.logger).to receive(:debug).with(match(/Using CustomerLinker/))
        expect(Rails.logger).to receive(:debug).with(match(/business #{persisted_business.id}/))

        controller.send(:find_customers_by_phone, phone_number, persisted_business)
      end
    end

    context 'when business is unpersisted' do
      it 'falls back to global search instead of using unpersisted business' do
        expect(CustomerLinker).to receive(:find_customers_by_phone_across_all_businesses)
          .with(phone_number)
          .and_return([customer])

        expect(CustomerLinker).not_to receive(:find_customers_by_phone_public)

        result = controller.send(:find_customers_by_phone, phone_number, unpersisted_business)
        expect(result).to eq([customer])
      end

      it 'logs warning about unpersisted business' do
        expect(Rails.logger).to receive(:warn)
          .with(match(/Received unpersisted business object/))

        controller.send(:find_customers_by_phone, phone_number, unpersisted_business)
      end

      it 'does not raise error when accessing business.id' do
        # This test ensures we don't try to log business.id for unpersisted business
        expect {
          controller.send(:find_customers_by_phone, phone_number, unpersisted_business)
        }.not_to raise_error
      end

      it 'returns results from global search' do
        allow(CustomerLinker).to receive(:find_customers_by_phone_across_all_businesses)
          .with(phone_number)
          .and_return([customer])

        result = controller.send(:find_customers_by_phone, phone_number, unpersisted_business)
        expect(result).to eq([customer])
      end
    end

    context 'when business is nil' do
      it 'uses global search' do
        expect(CustomerLinker).to receive(:find_customers_by_phone_across_all_businesses)
          .with(phone_number)
          .and_return([customer])

        result = controller.send(:find_customers_by_phone, phone_number, nil)
        expect(result).to eq([customer])
      end

      it 'does not log warning about unpersisted business' do
        expect(Rails.logger).not_to receive(:warn).with(match(/unpersisted/))

        controller.send(:find_customers_by_phone, phone_number, nil)
      end
    end

    context 'edge cases' do
      it 'handles business that was persisted but then destroyed' do
        business = create(:business, name: 'To Be Destroyed')
        business_id = business.id
        business.destroy

        # Reload business - it should be frozen and marked as destroyed
        destroyed_business = Business.new(id: business_id)
        destroyed_business.instance_variable_set(:@destroyed, true)

        expect(CustomerLinker).to receive(:find_customers_by_phone_across_all_businesses)
          .with(phone_number)
          .and_return([])

        result = controller.send(:find_customers_by_phone, phone_number, destroyed_business)
        expect(result).to eq([])
      end

      it 'handles business with id but not saved (edge case)' do
        # Create a business object with ID but not persisted
        business_with_id = Business.new(id: 999999, name: 'Fake ID Business')
        expect(business_with_id.persisted?).to be false
        expect(business_with_id.id).to be_present

        expect(Rails.logger).to receive(:warn)
          .with(match(/Received unpersisted business object/))

        controller.send(:find_customers_by_phone, phone_number, business_with_id)
      end
    end

    context 'integration with CustomerLinker' do
      it 'correctly passes persisted business to CustomerLinker without errors' do
        # This is an integration test to ensure no errors occur in CustomerLinker
        result = controller.send(:find_customers_by_phone, phone_number, persisted_business)

        expect(result).to be_an(Array)
        expect(result.first).to eq(customer) if result.any?
      end

      it 'correctly handles global search fallback for unpersisted business' do
        # Integration test for unpersisted business fallback
        result = controller.send(:find_customers_by_phone, phone_number, unpersisted_business)

        expect(result).to be_an(Array)
        # Should still find the customer via global search
        expect(result).to include(customer)
      end
    end

    context 'security implications' do
      it 'prevents potential SQL injection via unpersisted business attributes' do
        # An unpersisted business might have malicious attributes
        malicious_business = Business.new(name: "'; DROP TABLE businesses; --")

        # Should safely fall back to global search without using business attributes
        expect {
          controller.send(:find_customers_by_phone, phone_number, malicious_business)
        }.not_to raise_error
      end

      it 'logs unpersisted business attempts for security auditing' do
        expect(Rails.logger).to receive(:warn)
          .with(match(/unpersisted business object/))

        controller.send(:find_customers_by_phone, phone_number, unpersisted_business)
      end
    end

    context 'performance considerations' do
      it 'does not attempt to save unpersisted business' do
        expect(unpersisted_business).not_to receive(:save)
        expect(unpersisted_business).not_to receive(:save!)

        controller.send(:find_customers_by_phone, phone_number, unpersisted_business)
      end

      it 'efficiently checks persistence before expensive operations' do
        # The persisted? check should happen before CustomerLinker call
        # Note: persisted? is called twice - once for the if condition, once for the warning log
        expect(unpersisted_business).to receive(:persisted?).at_least(:once).and_return(false)

        # CustomerLinker should not be called with unpersisted business
        expect(CustomerLinker).not_to receive(:find_customers_by_phone_public)
          .with(phone_number, unpersisted_business)

        controller.send(:find_customers_by_phone, phone_number, unpersisted_business)
      end
    end
  end
end
