# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Quickbooks::ExportInvoicesJob, type: :job do
  let(:business) { create(:business) }
  let(:user) { create(:user, :manager, business: business) }

  before do
    ActsAsTenant.current_tenant = business
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  it 'marks export_run failed when no connection' do
    run = business.quickbooks_export_runs.create!(
      user: user,
      status: :queued,
      export_type: 'invoices',
      filters: { range_start: Date.current.iso8601, range_end: Date.current.iso8601, invoice_statuses: ['paid'] }
    )

    described_class.perform_now(run.id)

    expect(run.reload).to be_failed
    expect(run.error_report.dig('errors', 0, 'type')).to eq('missing_connection')
  end

  it 'respects invoice_ids filter when present' do
    connection = business.create_quickbooks_connection!(realm_id: '123', access_token: 'x', refresh_token: 'y', active: true, config: {})

    inv1 = create(:invoice, :paid, business: business)
    inv2 = create(:invoice, :paid, business: business)

    run = business.quickbooks_export_runs.create!(
      user: user,
      status: :queued,
      export_type: 'invoices',
      filters: {
        range_start: 1.day.ago.to_date.iso8601,
        range_end: Date.current.iso8601,
        invoice_statuses: ['paid'],
        invoice_ids: [inv2.id]
      }
    )

    exporter = instance_double(Quickbooks::InvoiceExporter)
    expect(Quickbooks::InvoiceExporter).to receive(:new).and_return(exporter)

    expect(exporter).to receive(:export_invoices!) do |args|
      ids = args.fetch(:invoices).pluck(:id)
      expect(ids).to eq([inv2.id])
      { exported: 1, skipped_already_exported: 0, failed: 0, payments_exported: 0, payments_failed: 0, failures: [] }
    end

    described_class.perform_now(run.id)

    expect(run.reload).to be_succeeded
    expect(run.summary['exported']).to eq(1)
  end
end
