# frozen_string_literal: true

module Quickbooks
  class ExportInvoicesJob < ApplicationJob
    queue_as :default

    def perform(export_run_id)
      export_run = QuickbooksExportRun.find(export_run_id)
      business = export_run.business

      connection = business.quickbooks_connection
      unless connection&.active?
        export_run.fail!(error_report: { errors: [{ type: 'missing_connection', message: 'QuickBooks is not connected.' }] })
        return
      end

      ActsAsTenant.with_tenant(business) do
        export_run.start!

        range_start = Date.iso8601(export_run.filters.fetch('range_start'))
        range_end = Date.iso8601(export_run.filters.fetch('range_end'))
        statuses = Array(export_run.filters.fetch('invoice_statuses', %w[paid])).map(&:to_s)
        invoice_ids = Array(export_run.filters['invoice_ids']).map(&:to_i).select { |id| id.positive? }

        invoices = business.invoices
                          .where(status: statuses)
                          .where(created_at: range_start.beginning_of_day..range_end.end_of_day)
                          .includes(:tenant_customer, :payments)

        invoices = invoices.where(id: invoice_ids) if invoice_ids.any?

        exporter = Quickbooks::InvoiceExporter.new(business: business, connection: connection)
        results = exporter.export_invoices!(invoices: invoices, export_payments: export_run.filters['export_payments'] == true)

        summary = {
          range_start: range_start.iso8601,
          range_end: range_end.iso8601,
          invoice_statuses: statuses,
          exported: results[:exported],
          skipped_already_exported: results[:skipped_already_exported],
          failed: results[:failed],
          payments_exported: results[:payments_exported],
          payments_failed: results[:payments_failed]
        }

        error_report = { failures: results[:failures] }

        if results[:failed].to_i.zero?
          export_run.succeed!(summary: summary, error_report: error_report)
        elsif results[:exported].to_i.positive?
          export_run.partial!(summary: summary, error_report: error_report)
        else
          export_run.fail!(error_report: error_report)
        end
      end
    rescue => e
      Rails.logger.error("[Quickbooks::ExportInvoicesJob] Failed: #{e.class}: #{e.message}")
      Rails.logger.error(e.backtrace.first(10).join("\n"))

      begin
        export_run&.fail!(error_report: { errors: [{ type: 'exception', message: e.message, class: e.class.name }] })
      rescue
        nil
      end

      raise
    end
  end
end
