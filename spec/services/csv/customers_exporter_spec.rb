# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Csv::CustomersExporter do
  let(:business) { create(:business) }
  let(:exporter) { described_class.new(business: business) }

  describe '#export' do
    it 'generates CSV with customer data' do
      customer = create(:tenant_customer,
        business: business,
        email: 'test@example.com',
        first_name: 'John',
        last_name: 'Doe',
        phone: '555-1234',
        active: true
      )

      csv = exporter.export
      parsed = CSV.parse(csv, headers: true)

      expect(parsed.headers).to include('ID', 'Email', 'First Name', 'Last Name')
      row = parsed.first
      expect(row['Email']).to eq('test@example.com')
      expect(row['First Name']).to eq('John')
      expect(row['Last Name']).to eq('Doe')
    end

    it 'exports all customers for the business' do
      create_list(:tenant_customer, 3, business: business)
      csv = exporter.export
      parsed = CSV.parse(csv, headers: true)

      expect(parsed.length).to eq(3)
    end

    it 'does not include customers from other businesses' do
      other_business = create(:business)
      create(:tenant_customer, business: business)
      create(:tenant_customer, business: other_business)

      csv = exporter.export
      parsed = CSV.parse(csv, headers: true)

      expect(parsed.length).to eq(1)
    end
  end

  describe '#template' do
    it 'includes headers and sample row' do
      csv = exporter.template
      parsed = CSV.parse(csv)

      expect(parsed.first).to include('Email', 'First Name', 'Last Name')
      expect(parsed.length).to eq(2) # headers + sample
      expect(parsed.last).to include('customer@example.com')
    end
  end

  describe '#filename' do
    it 'uses customers as the export name' do
      expect(exporter.filename).to start_with('customers-')
    end
  end

  describe 'headers' do
    it 'includes all expected columns' do
      csv = exporter.export
      headers = CSV.parse(csv).first

      expected_headers = [
        'ID', 'Email', 'First Name', 'Last Name', 'Phone',
        'Address', 'Notes', 'Active', 'Phone Opt-In',
        'Email Marketing Opt-Out', 'Created At', 'Last Booking'
      ]

      expect(headers).to eq(expected_headers)
    end
  end
end

