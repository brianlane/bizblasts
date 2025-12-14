# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Quickbooks::InvoiceExporter do
  let(:business) { create(:business) }
  let(:connection) { business.create_quickbooks_connection!(realm_id: '123', access_token: 'x', refresh_token: 'y', active: true, config: {}) }

  it 'escapes apostrophes for QBO query strings by doubling them' do
    exporter = described_class.new(business: business, connection: connection)

    expect(exporter.send(:escape_qbo_string, "O'Brien")).to eq("O''Brien")
  end
end
