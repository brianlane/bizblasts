# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StaggeredEmailService, type: :service do
  let(:business) { create(:business) }
  let(:tenant_customer) { create(:tenant_customer, business: business) }
  let(:order) { create(:order, business: business, tenant_customer: tenant_customer, order_type: :service) }
  let(:service) { create(:service, business: business) }
  let(:staff_member) { create(:staff_member, business: business) }

  before do
    # Clear email deliveries
    ActionMailer::Base.deliveries.clear
    
    # Create a service line item for the order
    order.line_items.create!(
      service: service,
      staff_member: staff_member,
      quantity: 1,
      price: 100.0,
      total_amount: 100.0
    )
  end

  describe '.deliver_specifications' do
    let(:email_specs) do
      [
        double('email_spec_1', execute: true, execute_with_delay: true),
        double('email_spec_2', execute: true, execute_with_delay: true)
      ]
    end

    it 'delivers email specifications with staggered timing' do
      result = described_class.deliver_specifications(email_specs, delay_between_emails: 1.second)

      expect(email_specs[0]).to have_received(:execute)
      expect(email_specs[1]).to have_received(:execute_with_delay).with(wait: 1.second)
      expect(result).to eq(2)
    end

    it 'handles empty specifications array gracefully' do
      expect { described_class.deliver_specifications([]) }.not_to raise_error
    end

    it 'continues processing when individual emails fail' do
      failing_spec = double('failing_spec', execute: false)
      passing_spec = double('passing_spec', execute_with_delay: true)

      result = described_class.deliver_specifications([failing_spec, passing_spec])
      expect(result).to eq(1)
    end
  end

  describe '.deliver_multiple (legacy)' do
    it 'delivers emails with staggered timing' do
      # Create mock email jobs
      email1 = double('email1')
      email2 = double('email2')  
      email3 = double('email3')
      
      # In test environment, all emails are sent immediately without delays
      expect(email1).to receive(:deliver_later)
      expect(email2).to receive(:deliver_later)
      expect(email3).to receive(:deliver_later)
      
      described_class.deliver_multiple([email1, email2, email3], delay_between_emails: 1.second)
    end

    it 'handles empty email array gracefully' do
      expect { described_class.deliver_multiple([]) }.not_to raise_error
    end

    it 'filters out nil emails and handles remaining emails' do
      email1 = double('email1')
      email3 = double('email3')
      
      # In test environment, all emails are sent immediately without delays
      expect(email1).to receive(:deliver_later)
      expect(email3).to receive(:deliver_later)
      
      described_class.deliver_multiple([email1, nil, email3])
    end

    it 'handles all nil emails gracefully' do
      expect { described_class.deliver_multiple([nil, nil, nil]) }.not_to raise_error
    end

    it 'logs deprecation warning' do
      expect(Rails.logger).to receive(:warn).with(/deliver_multiple is deprecated/)
      described_class.deliver_multiple([])
    end
  end

  describe '.deliver_order_emails' do
    it 'runs without raising errors and returns success count' do
      result = nil
      expect { result = described_class.deliver_order_emails(order) }.not_to raise_error
      expect(result).to be_a(Integer)
      expect(result).to be >= 0
    end

    it 'handles errors gracefully and returns 0' do
      # Make EmailCollectionBuilder raise an error
      allow(EmailCollectionBuilder).to receive(:new).and_raise(StandardError.new('Test error'))

      result = nil
      expect { result = described_class.deliver_order_emails(order) }.not_to raise_error
      expect(result).to eq(0)
    end

    it 'uses EmailCollectionBuilder to build specifications' do
      builder = instance_double(EmailCollectionBuilder)
      allow(EmailCollectionBuilder).to receive(:new).and_return(builder)
      allow(builder).to receive(:add_order_emails).with(order).and_return(builder)
      allow(builder).to receive(:build).and_return([])

      described_class.deliver_order_emails(order)

      expect(builder).to have_received(:add_order_emails).with(order)
      expect(builder).to have_received(:build)
    end
  end

  describe '.deliver_booking_emails' do
    let(:booking) { create(:booking, business: business, tenant_customer: tenant_customer, service: service, staff_member: staff_member) }

    it 'runs without raising errors and returns success count' do
      result = nil
      expect { result = described_class.deliver_booking_emails(booking) }.not_to raise_error
      expect(result).to be_a(Integer)
      expect(result).to be >= 0
    end

    it 'handles errors gracefully and returns 0' do
      # Make EmailCollectionBuilder raise an error
      allow(EmailCollectionBuilder).to receive(:new).and_raise(StandardError.new('Test error'))

      result = nil
      expect { result = described_class.deliver_booking_emails(booking) }.not_to raise_error
      expect(result).to eq(0)
    end
  end

  describe '.deliver_with_strategy' do
    let(:email_specs) do
      [
        double('email_spec', execute: true, execute_with_delay: true)
      ]
    end

    it 'supports immediate delivery strategy' do
      result = described_class.deliver_with_strategy(email_specs, strategy: :immediate)
      expect(result).to eq(1)
    end

    it 'supports time_staggered delivery strategy' do
      result = described_class.deliver_with_strategy(email_specs, strategy: :time_staggered, delay_between_emails: 2.seconds)
      expect(result).to eq(1)
    end

    it 'supports batch_staggered delivery strategy' do
      result = described_class.deliver_with_strategy(email_specs, strategy: :batch_staggered, batch_size: 2, batch_delay: 3.seconds)
      expect(result).to eq(1)
    end

    it 'raises error for unknown strategy' do
      expect {
        described_class.deliver_with_strategy(email_specs, strategy: :unknown)
      }.to raise_error(ArgumentError, /Unknown delivery strategy/)
    end
  end

  describe 'rate limit prevention' do
    it 'uses appropriate delay to stay under Resend 2/second limit' do
      email_specs = [
        double('email_spec_1', execute: true),
        double('email_spec_2', execute_with_delay: true)
      ]
      
      described_class.deliver_specifications(email_specs, delay_between_emails: 1.second)
      
      expect(email_specs[1]).to have_received(:execute_with_delay).with(wait: 1.second)
    end
  end
end 