# frozen_string_literal: true

module Csv
  class ProcessImportJob < ApplicationJob
    queue_as :default

    def perform(import_run_id)
      # Find the import run without tenant scoping first
      import_run = ActsAsTenant.without_tenant { CsvImportRun.find(import_run_id) }
      business = import_run.business

      # Process within tenant scope
      ActsAsTenant.with_tenant(business) do
        import_run = CsvImportRun.find(import_run_id)
        import_run.start!

        importer = importer_for(import_run.import_type, business, import_run)
        importer.import
      end
    rescue StandardError => e
      Rails.logger.error("[Csv::ProcessImportJob] Failed: #{e.class}: #{e.message}")
      Rails.logger.error(e.backtrace.first(10).join("\n"))

      begin
        import_run&.fail!(error_report: {
          errors: [{ type: 'exception', message: e.message, class: e.class.name }]
        })
      rescue StandardError
        # Swallow errors during cleanup
      end

      raise
    end

    private

    def importer_for(import_type, business, import_run)
      case import_type
      when 'customers'
        Csv::CustomersImporter.new(business: business, import_run: import_run)
      when 'products'
        Csv::ProductsImporter.new(business: business, import_run: import_run)
      when 'services'
        Csv::ServicesImporter.new(business: business, import_run: import_run)
      when 'bookings'
        Csv::BookingsImporter.new(business: business, import_run: import_run)
      when 'invoices'
        Csv::InvoicesImporter.new(business: business, import_run: import_run)
      when 'orders'
        Csv::OrdersImporter.new(business: business, import_run: import_run)
      when 'payments'
        Csv::PaymentsImporter.new(business: business, import_run: import_run)
      when 'customer_subscriptions'
        Csv::CustomerSubscriptionsImporter.new(business: business, import_run: import_run)
      else
        raise ArgumentError, "Unknown import type: #{import_type}"
      end
    end
  end
end
