# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'BusinessManager::Transactions CSV Download', type: :request do
  let!(:business) { create(:business, :standard) }
  let!(:manager) { create(:user, :manager, business: business) }
  let!(:customer) { create(:tenant_customer, business: business) }
  let!(:order) { create(:order, business: business, tenant_customer: customer) }

  before do
    # Set the host to the business's hostname for tenant scoping
    host! "#{business.hostname}.lvh.me"
    # Set the tenant context
    ActsAsTenant.current_tenant = business
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe 'GET /manage/transactions/download_csv' do
    context 'when signed in as manager' do
      before do
        sign_in manager
      end

      it 'downloads CSV file with transactions' do
        get download_csv_business_manager_transactions_path(format: :csv)
        
        expect(response).to have_http_status(:success)
        expect(response.content_type).to include('text/csv')
        expect(response.headers['Content-Disposition']).to include('attachment')
        expect(response.headers['Content-Disposition']).to include('.csv')
      end

      it 'includes correct CSV headers' do
        get download_csv_business_manager_transactions_path(format: :csv)
        
        csv_content = response.body
        lines = csv_content.split("\n")
        headers = lines.first.split(',')
        
        expect(headers).to include('Transaction ID')
        expect(headers).to include('Type')
        expect(headers).to include('Date')
        expect(headers).to include('Customer Name')
        expect(headers).to include('Total Amount')
      end

      it 'includes transaction data in CSV' do
        get download_csv_business_manager_transactions_path(format: :csv)
        
        csv_content = response.body
        expect(csv_content).to include(order.order_number)
        expect(csv_content).to include(customer.full_name)
      end

      it 'respects filter parameters' do
        get download_csv_business_manager_transactions_path(filter: 'orders', format: :csv)
        
        expect(response).to have_http_status(:success)
        expect(response.body).to include(order.order_number)
      end
    end
  end
end