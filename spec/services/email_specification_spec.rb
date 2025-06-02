# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EmailSpecification, type: :service do
  let(:business) { create(:business) }
  let(:tenant_customer) { create(:tenant_customer, business: business) }
  let(:order) { create(:order, business: business, tenant_customer: tenant_customer) }

  describe 'initialization' do
    it 'creates a valid specification with required arguments' do
      spec = EmailSpecification.new(
        mailer_class: BusinessMailer,
        method_name: :new_order_notification,
        arguments: [order]
      )

      expect(spec.mailer_class).to eq(BusinessMailer)
      expect(spec.method_name).to eq(:new_order_notification)
      expect(spec.arguments).to eq([order])
      expect(spec.condition).to be_nil
    end

    it 'accepts a condition callable' do
      condition = -> { true }
      spec = EmailSpecification.new(
        mailer_class: BusinessMailer,
        method_name: :new_order_notification,
        arguments: [order],
        condition: condition
      )

      expect(spec.condition).to eq(condition)
    end

    it 'freezes the specification making it immutable' do
      spec = EmailSpecification.new(
        mailer_class: BusinessMailer,
        method_name: :new_order_notification,
        arguments: [order]
      )

      expect(spec).to be_frozen
      expect(spec.arguments).to be_frozen
    end

    it 'converts method_name to symbol' do
      spec = EmailSpecification.new(
        mailer_class: BusinessMailer,
        method_name: 'new_order_notification',
        arguments: [order]
      )

      expect(spec.method_name).to eq(:new_order_notification)
    end
  end

  describe 'validation' do
    it 'raises error for invalid mailer_class' do
      expect {
        EmailSpecification.new(
          mailer_class: "not a class",
          method_name: :new_order_notification,
          arguments: [order]
        )
      }.to raise_error(ArgumentError, "mailer_class must be a class")
    end

    it 'raises error when mailer_class does not respond to method' do
      expect {
        EmailSpecification.new(
          mailer_class: BusinessMailer,
          method_name: :nonexistent_method,
          arguments: [order]
        )
      }.to raise_error(ArgumentError, "mailer_class must respond to nonexistent_method")
    end

    it 'raises error for invalid arguments' do
      expect {
        EmailSpecification.new(
          mailer_class: BusinessMailer,
          method_name: :new_order_notification,
          arguments: "not an array"
        )
      }.to raise_error(ArgumentError, "arguments must be an array")
    end

    it 'raises error for non-callable condition' do
      expect {
        EmailSpecification.new(
          mailer_class: BusinessMailer,
          method_name: :new_order_notification,
          arguments: [order],
          condition: "not callable"
        )
      }.to raise_error(ArgumentError, "condition must be callable")
    end
  end

  describe '#execute' do
    let(:spec) do
      EmailSpecification.new(
        mailer_class: BusinessMailer,
        method_name: :new_order_notification,
        arguments: [order]
      )
    end

    before do
      ActionMailer::Base.deliveries.clear
    end

    it 'executes the mailer method and delivers later' do
      # Mock the mailer to avoid actual email sending
      mailer_instance = double('mailer_instance')
      allow(BusinessMailer).to receive(:new_order_notification).with(order).and_return(mailer_instance)
      expect(mailer_instance).to receive(:deliver_later)

      result = spec.execute
      expect(result).to be true
    end

    it 'returns false when mailer method returns nil' do
      allow(BusinessMailer).to receive(:new_order_notification).with(order).and_return(nil)

      result = spec.execute
      expect(result).to be false
    end

    it 'handles errors gracefully and returns false' do
      allow(BusinessMailer).to receive(:new_order_notification).and_raise(StandardError.new('Test error'))

      result = spec.execute
      expect(result).to be false
    end

    context 'with condition' do
      it 'executes when condition returns true' do
        spec_with_condition = EmailSpecification.new(
          mailer_class: BusinessMailer,
          method_name: :new_order_notification,
          arguments: [order],
          condition: -> { true }
        )

        mailer_instance = double('mailer_instance')
        allow(BusinessMailer).to receive(:new_order_notification).with(order).and_return(mailer_instance)
        expect(mailer_instance).to receive(:deliver_later)

        result = spec_with_condition.execute
        expect(result).to be true
      end

      it 'does not execute when condition returns false' do
        spec_with_condition = EmailSpecification.new(
          mailer_class: BusinessMailer,
          method_name: :new_order_notification,
          arguments: [order],
          condition: -> { false }
        )

        expect(BusinessMailer).not_to receive(:new_order_notification)

        result = spec_with_condition.execute
        expect(result).to be false
      end

      it 'handles condition errors gracefully' do
        spec_with_condition = EmailSpecification.new(
          mailer_class: BusinessMailer,
          method_name: :new_order_notification,
          arguments: [order],
          condition: -> { raise StandardError.new('Condition error') }
        )

        expect(BusinessMailer).not_to receive(:new_order_notification)

        result = spec_with_condition.execute
        expect(result).to be false
      end
    end
  end

  describe '#execute_with_delay' do
    let(:spec) do
      EmailSpecification.new(
        mailer_class: BusinessMailer,
        method_name: :new_order_notification,
        arguments: [order]
      )
    end

    before do
      ActionMailer::Base.deliveries.clear
    end

    it 'executes the mailer method with delay in non-test environment' do
      allow(Rails.env).to receive(:test?).and_return(false)
      
      mailer_instance = double('mailer_instance')
      allow(BusinessMailer).to receive(:new_order_notification).with(order).and_return(mailer_instance)
      expect(mailer_instance).to receive(:deliver_later).with(wait: 5.seconds)

      result = spec.execute_with_delay(wait: 5.seconds)
      expect(result).to be true
    end

    it 'executes without delay in test environment' do
      allow(Rails.env).to receive(:test?).and_return(true)
      
      mailer_instance = double('mailer_instance')
      allow(BusinessMailer).to receive(:new_order_notification).with(order).and_return(mailer_instance)
      expect(mailer_instance).to receive(:deliver_later).with(no_args)

      result = spec.execute_with_delay(wait: 5.seconds)
      expect(result).to be true
    end

    it 'returns false when mailer method returns nil' do
      allow(BusinessMailer).to receive(:new_order_notification).with(order).and_return(nil)

      result = spec.execute_with_delay(wait: 5.seconds)
      expect(result).to be false
    end

    it 'handles errors gracefully and returns false' do
      allow(BusinessMailer).to receive(:new_order_notification).and_raise(StandardError.new('Test error'))

      result = spec.execute_with_delay(wait: 5.seconds)
      expect(result).to be false
    end
  end

  describe '#description' do
    it 'returns a human-readable description' do
      spec = EmailSpecification.new(
        mailer_class: BusinessMailer,
        method_name: :new_order_notification,
        arguments: [order, tenant_customer]
      )

      expected = "BusinessMailer.new_order_notification(Order, TenantCustomer)"
      expect(spec.description).to eq(expected)
    end

    it 'handles empty arguments' do
      spec = EmailSpecification.new(
        mailer_class: BusinessMailer,
        method_name: :new_order_notification,
        arguments: []
      )

      expected = "BusinessMailer.new_order_notification()"
      expect(spec.description).to eq(expected)
    end
  end
end 