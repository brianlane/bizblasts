# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EmailMarketing::Mailchimp::Client do
  let(:business) { create(:business) }
  let(:connection) { create(:email_marketing_connection, :mailchimp, :with_list, business: business) }
  let(:client) { described_class.new(connection) }
  let(:customer) { create(:tenant_customer, business: business, first_name: 'John', last_name: 'Doe', email: 'john@example.com', phone: '+15551234567') }

  describe '#get_lists' do
    it 'returns a list of audiences' do
      mock_response = {
        'lists' => [
          {
            'id' => 'list123',
            'name' => 'Main Newsletter',
            'stats' => { 'member_count' => 1000, 'unsubscribe_count' => 50 },
            'date_created' => '2024-01-01T00:00:00Z'
          }
        ]
      }

      allow(client).to receive(:http_request).and_return(
        EmailMarketing::BaseClient::ApiResponse.new(success: true, status: 200, body: mock_response, raw_response: nil)
      )

      lists = client.get_lists

      expect(lists).to be_an(Array)
      expect(lists.first[:id]).to eq('list123')
      expect(lists.first[:name]).to eq('Main Newsletter')
      expect(lists.first[:member_count]).to eq(1000)
    end
  end

  describe '#add_contact' do
    it 'adds a customer to the list' do
      mock_response = {
        'email_address' => customer.email,
        'status' => 'subscribed',
        'merge_fields' => { 'FNAME' => 'John', 'LNAME' => 'Doe' }
      }

      allow(client).to receive(:http_request).and_return(
        EmailMarketing::BaseClient::ApiResponse.new(success: true, status: 200, body: mock_response, raw_response: nil)
      )

      result = client.add_contact(customer)

      expect(result[:success]).to be true
      expect(result[:subscriber_hash]).to be_present
    end

    it 'updates customer with mailchimp info on success' do
      mock_response = { 'email_address' => customer.email, 'status' => 'subscribed' }

      allow(client).to receive(:http_request).and_return(
        EmailMarketing::BaseClient::ApiResponse.new(success: true, status: 200, body: mock_response, raw_response: nil)
      )

      client.add_contact(customer)

      customer.reload
      expect(customer.mailchimp_subscriber_hash).to be_present
      expect(customer.mailchimp_list_id).to eq(connection.default_list_id)
      expect(customer.email_marketing_synced_at).to be_present
    end
  end

  describe '#remove_contact' do
    before do
      customer.update!(mailchimp_subscriber_hash: 'abc123', mailchimp_list_id: connection.default_list_id)
    end

    it 'unsubscribes the contact' do
      mock_response = { 'status' => 'unsubscribed' }

      allow(client).to receive(:http_request).and_return(
        EmailMarketing::BaseClient::ApiResponse.new(success: true, status: 200, body: mock_response, raw_response: nil)
      )

      result = client.remove_contact(customer)

      expect(result[:success]).to be true
      expect(result[:action]).to eq('unsubscribed')
    end
  end

  describe '#batch_add_contacts' do
    let(:customers) { create_list(:tenant_customer, 3, business: business) }

    it 'queues a batch operation' do
      mock_response = { 'id' => 'batch123', 'status' => 'pending', 'total_operations' => 3 }

      allow(client).to receive(:http_request).and_return(
        EmailMarketing::BaseClient::ApiResponse.new(success: true, status: 200, body: mock_response, raw_response: nil)
      )

      result = client.batch_add_contacts(customers)

      expect(result[:success]).to be true
      expect(result[:batch_id]).to eq('batch123')
      expect(result[:operation_count]).to eq(3)
    end
  end

  describe 'email hash generation' do
    it 'generates consistent MD5 hash for email addresses' do
      # Mailchimp uses MD5 hash of lowercase email
      hash1 = Digest::MD5.hexdigest('john@example.com')
      hash2 = Digest::MD5.hexdigest('JOHN@EXAMPLE.COM'.downcase)

      expect(hash1).to eq(hash2)
    end
  end
end
