# frozen_string_literal: true

module BusinessManager
  class CsvController < BusinessManager::BaseController
    before_action :set_import_run, only: [:import_status, :import_errors]

    VALID_TYPES = CsvImportRun::IMPORT_TYPES.freeze

    # GET /manage/csv
    def index
      authorize :csv, :index?
      @import_runs = @current_business.csv_import_runs
                                      .order(created_at: :desc)
                                      .limit(20)
    end

    # GET /manage/csv/export/:type
    def export
      authorize :csv, :export?
      validate_type!

      exporter = exporter_for(params[:type])

      respond_to do |format|
        format.csv do
          csv_data = exporter.export
          send_data csv_data,
                    filename: exporter.filename,
                    type: 'text/csv'
        end
      end
    end

    # GET /manage/csv/template/:type
    def template
      authorize :csv, :export?
      validate_type!

      exporter = exporter_for(params[:type])

      respond_to do |format|
        format.csv do
          csv_data = exporter.template
          send_data csv_data,
                    filename: "#{params[:type]}-template.csv",
                    type: 'text/csv'
        end
      end
    end

    # GET /manage/csv/import/:type
    def import_form
      authorize :csv, :import?
      validate_type!

      @import_type = params[:type]
      @recent_imports = @current_business.csv_import_runs
                                         .where(import_type: @import_type)
                                         .order(created_at: :desc)
                                         .limit(5)
    end

    # POST /manage/csv/import/:type
    def import
      authorize :csv, :import?
      validate_type!

      unless params[:file].present?
        redirect_to import_form_business_manager_csv_index_path(type: params[:type]),
                    alert: 'Please select a file to import'
        return
      end

      import_run = @current_business.csv_import_runs.new(
        import_type: params[:type],
        user: current_user,
        original_filename: params[:file].original_filename
      )
      import_run.csv_file.attach(params[:file])

      if import_run.save
        Csv::ProcessImportJob.perform_later(import_run.id)
        redirect_to import_status_business_manager_csv_index_path(id: import_run.id),
                    notice: 'Import started. You can track progress below.'
      else
        redirect_to import_form_business_manager_csv_index_path(type: params[:type]),
                    alert: "Failed to start import: #{import_run.errors.full_messages.join(', ')}"
      end
    end

    # GET /manage/csv/import/:id/status
    def import_status
      authorize :csv, :import?

      respond_to do |format|
        format.html
        format.json do
          render json: {
            status: @import_run.status,
            progress: @import_run.progress_percentage,
            processed_rows: @import_run.processed_rows,
            total_rows: @import_run.total_rows,
            created_count: @import_run.created_count,
            updated_count: @import_run.updated_count,
            skipped_count: @import_run.skipped_count,
            error_count: @import_run.error_count,
            finished: @import_run.finished_at.present?
          }
        end
      end
    end

    # GET /manage/csv/import/:id/errors
    def import_errors
      authorize :csv, :import?
      @errors = @import_run.error_report['errors'] || []
    end

    private

    def set_import_run
      @import_run = @current_business.csv_import_runs.find(params[:id])
    end

    def validate_type!
      return if VALID_TYPES.include?(params[:type])

      raise ActionController::RoutingError, "Unknown CSV type: #{params[:type]}"
    end

    def exporter_for(type)
      case type
      when 'customers'
        Csv::CustomersExporter.new(business: @current_business)
      when 'products'
        Csv::ProductsExporter.new(business: @current_business)
      when 'services'
        Csv::ServicesExporter.new(business: @current_business)
      when 'bookings'
        Csv::BookingsExporter.new(business: @current_business)
      when 'invoices'
        Csv::InvoicesExporter.new(business: @current_business)
      when 'orders'
        Csv::OrdersExporter.new(business: @current_business)
      when 'payments'
        Csv::PaymentsExporter.new(business: @current_business)
      when 'customer_subscriptions'
        Csv::CustomerSubscriptionsExporter.new(business: @current_business)
      else
        raise ActionController::RoutingError, "Unknown export type: #{type}"
      end
    end
  end
end
