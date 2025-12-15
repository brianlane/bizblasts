# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::TwilioController, 'CustomerLinker method usage' do
  let(:controller) { described_class.new }
  let(:business) { create(:business, sms_enabled: true) }
  let!(:customer) { create(:tenant_customer, business: business, phone: '+16026866672') }

  before do
    # Disable signature verification for these tests
    allow(controller).to receive(:verify_webhook_signature?).and_return(false)
  end

  describe '#find_customers_by_phone' do
    context 'Bug Fix: uses class methods consistently' do
      it 'calls CustomerLinker.find_customers_by_phone_public (class method) when business context exists' do
        expect(CustomerLinker).to receive(:find_customers_by_phone_public)
          .with('+16026866672', business)
          .and_return([customer])

        result = controller.send(:find_customers_by_phone, '+16026866672', business)
        expect(result).to eq([customer])
      end

      it 'calls CustomerLinker.find_customers_by_phone_across_all_businesses (class method) when no business context' do
        expect(CustomerLinker).to receive(:find_customers_by_phone_across_all_businesses)
          .with('+16026866672')
          .and_return([customer])

        result = controller.send(:find_customers_by_phone, '+16026866672', nil)
        expect(result).to eq([customer])
      end

      it 'does NOT create CustomerLinker instances for phone lookups' do
        # This verifies we're using class methods, not instance methods
        expect(CustomerLinker).not_to receive(:new)

        controller.send(:find_customers_by_phone, '+16026866672', business)
      end

      it 'returns Array consistently regardless of business context' do
        result_with_business = controller.send(:find_customers_by_phone, '+16026866672', business)
        result_without_business = controller.send(:find_customers_by_phone, '+16026866672', nil)

        expect(result_with_business).to be_an(Array)
        expect(result_without_business).to be_an(Array)
      end
    end

    context 'when CustomerLinker instance methods are used incorrectly' do
      it 'raises NoMethodError if trying to call instance method on class' do
        # This test documents what would happen if we called an instance method on the class
        expect {
          CustomerLinker.find_customers_by_phone('+16026866672')
        }.to raise_error(NoMethodError)
      end

      it 'raises ArgumentError if calling class method with wrong number of arguments' do
        # This verifies the class method signature
        expect {
          CustomerLinker.find_customers_by_phone_public('+16026866672') # Missing business parameter
        }.to raise_error(ArgumentError)
      end
    end
  end

  describe '#find_customers_by_phone_global' do
    it 'delegates to find_customers_by_phone with nil business' do
      expect(controller).to receive(:find_customers_by_phone).with('+16026866672', nil)

      controller.send(:find_customers_by_phone_global, '+16026866672')
    end
  end

  describe 'Bug Prevention: integration with customer linking' do
    context 'when finding business for auto-reply' do
      before do
        # Mock request for controller context
        controller.instance_variable_set(:@request, double('request', headers: {}))
      end

      it 'uses CustomerLinker class methods for customer lookups' do
        expect(CustomerLinker).to receive(:find_customers_by_phone_across_all_businesses)
          .with(customer.phone)
          .and_return([customer])

        result = controller.send(:find_business_for_auto_reply, customer.phone)
        expect(result).to eq(business)
      end
    end

    context 'when creating minimal customers' do
      let(:new_phone) { '+17775551234' }

      it 'creates customer using instance method when business context exists' do
        linker = CustomerLinker.new(business)
        allow(CustomerLinker).to receive(:new).with(business).and_return(linker)

        # This should NOT raise NoMethodError
        expect {
          controller.send(:create_minimal_customer, new_phone, business)
        }.not_to raise_error
      end
    end

    context 'when ensuring customer exists' do
      let(:new_phone) { '+17775559999' }

      it 'creates customer when user exists and needs linking' do
        user = create(:user, phone: new_phone, business: business)

        # Should not raise errors when linking user
        expect {
          controller.send(:ensure_customer_exists, new_phone, business)
        }.not_to raise_error

        # Verify customer was created or linked
        customer = TenantCustomer.find_by(phone: new_phone, business: business)
        expect(customer).to be_present
      end
    end
  end

  describe 'Method signature validation' do
    it 'verifies find_customers_by_phone uses correct CustomerLinker API' do
      # This test documents the expected behavior after Bug Fix
      # The controller should use class methods, not instance methods

      # With business context - uses class method
      allow(CustomerLinker).to receive(:find_customers_by_phone_public)
        .with('+16026866672', business)
        .and_return([customer])

      result = controller.send(:find_customers_by_phone, '+16026866672', business)
      expect(result).to eq([customer])

      # Without business context - uses different class method
      allow(CustomerLinker).to receive(:find_customers_by_phone_across_all_businesses)
        .with('+16026866672')
        .and_return([customer])

      result = controller.send(:find_customers_by_phone, '+16026866672', nil)
      expect(result).to eq([customer])
    end

    it 'ensures no instance method calls on CustomerLinker for phone lookups' do
      # Verify no instance is created for phone lookups (uses class methods instead)
      expect(CustomerLinker).not_to receive(:new)

      controller.send(:find_customers_by_phone, '+16026866672', business)
      controller.send(:find_customers_by_phone, '+16026866672', nil)
    end
  end
end
