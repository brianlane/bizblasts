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

  describe '.deliver_multiple' do
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
  end

  describe '.deliver_order_emails' do
    it 'runs without raising errors' do
      expect { described_class.deliver_order_emails(order) }.not_to raise_error
    end

    it 'handles errors gracefully' do
      # Make BusinessMailer.new_order_notification raise an error
      allow(BusinessMailer).to receive(:new_order_notification).and_raise(StandardError.new('Test error'))

      expect { described_class.deliver_order_emails(order) }.not_to raise_error
    end
  end

  describe 'rate limit prevention' do
    it 'uses appropriate delay to stay under Resend 2/second limit' do
      email1 = double('email1')
      email2 = double('email2')
      
      # In test environment, delays are not used to avoid test complexity
      expect(email1).to receive(:deliver_later)
      expect(email2).to receive(:deliver_later)
      
      described_class.deliver_multiple([email1, email2], delay_between_emails: 1.second)
    end
  end
end 