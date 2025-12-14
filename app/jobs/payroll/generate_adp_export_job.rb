# frozen_string_literal: true

module Payroll
  class GenerateAdpExportJob < ApplicationJob
    queue_as :default

    def perform(export_run_id)
      export_run = AdpPayrollExportRun.find(export_run_id)
      business = export_run.business

      ActsAsTenant.with_tenant(business) do
        export_run.start!

        config = business.adp_payroll_export_config || AdpPayrollExportConfig.create!(business: business)
        builder = Payroll::AdpCsvBuilder.new(business: business, config: config)

        csv_data, summary, error_report = builder.build(
          range_start: export_run.range_start,
          range_end: export_run.range_end
        )

        export_run.succeed!(csv_data: csv_data, summary: summary, error_report: error_report)
      end
    rescue => e
      Rails.logger.error("[Payroll::GenerateAdpExportJob] Failed: #{e.class}: #{e.message}")
      Rails.logger.error(e.backtrace.first(10).join("\n"))

      begin
        export_run&.fail!(error_report: { errors: [{ type: 'exception', message: e.message, class: e.class.name }] })
      rescue
        # swallow
      end

      raise
    end
  end
end
