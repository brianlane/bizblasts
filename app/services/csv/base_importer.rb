# frozen_string_literal: true

require 'csv'

module Csv
  class BaseImporter
    MAX_FILE_SIZE = 10.megabytes
    MAX_ROWS = 10_000

    attr_reader :business, :import_run, :errors

    def initialize(business:, import_run:)
      @business = business
      @import_run = import_run
      @errors = []
    end

    def import
      validate_file!
      return false if errors.any?

      rows = parse_csv
      return false if errors.any?

      import_run.update!(total_rows: rows.count)

      rows.each_with_index do |row, index|
        process_row(row, index + 2) # +2 for 1-indexed and header row
      end

      finalize_import
      true
    rescue CSV::MalformedCSVError => e
      errors << { row: 0, message: "Invalid CSV format: #{e.message}" }
      finalize_import
      false
    rescue StandardError => e
      errors << { row: 0, message: "Import failed: #{e.message}" }
      Rails.logger.error("[Csv::BaseImporter] Import failed: #{e.class}: #{e.message}")
      Rails.logger.error(e.backtrace.first(10).join("\n"))
      finalize_import
      false
    end

    protected

    def process_row(row, row_number)
      raise NotImplementedError, "Subclasses must implement #process_row"
    end

    def required_headers
      raise NotImplementedError, "Subclasses must implement #required_headers"
    end

    def find_existing_record(row)
      nil # Override in subclasses that support updates
    end

    def build_attributes(row)
      raise NotImplementedError, "Subclasses must implement #build_attributes"
    end

    def add_error(row_number, message)
      errors << { row: row_number, message: message }
      import_run.increment_progress!(error: true)
    end

    def parse_boolean(value, default: false)
      return default if value.blank?
      %w[true yes 1 t y].include?(value.to_s.strip.downcase)
    end

    def parse_decimal(value)
      return nil if value.blank?
      BigDecimal(value.to_s.strip.gsub(/[^\d.-]/, ''))
    rescue ArgumentError
      nil
    end

    def parse_integer(value)
      return nil if value.blank?
      value.to_s.strip.to_i
    end

    def parse_datetime(value)
      return nil if value.blank?
      Time.zone.parse(value.to_s.strip)
    rescue ArgumentError
      nil
    end

    def parse_date(value)
      return nil if value.blank?
      Date.parse(value.to_s.strip)
    rescue ArgumentError
      nil
    end

    private

    def validate_file!
      unless import_run.csv_file.attached?
        errors << { row: 0, message: 'No file attached' }
        return
      end

      if import_run.csv_file.blob.byte_size > MAX_FILE_SIZE
        errors << { row: 0, message: "File too large (max #{MAX_FILE_SIZE / 1.megabyte}MB)" }
      end
    end

    def parse_csv
      content = import_run.csv_file.download
      # Handle BOM and normalize line endings
      content = content.force_encoding('UTF-8')
                       .encode('UTF-8', invalid: :replace, undef: :replace)
                       .gsub(/\r\n?/, "\n")
                       .sub(/\A\xEF\xBB\xBF/, '') # Remove UTF-8 BOM

      rows = CSV.parse(content, headers: true, header_converters: ->(h) { h&.strip&.downcase })

      if rows.count > MAX_ROWS
        errors << { row: 0, message: "Too many rows (max #{MAX_ROWS})" }
        return []
      end

      validate_headers!(rows.headers)
      return [] if errors.any?

      rows
    end

    def validate_headers!(headers)
      normalized_headers = headers.compact.map { |h| h.to_s.strip.downcase.gsub(/\s+/, '_') }
      normalized_required = required_headers.map { |h| h.to_s.strip.downcase.gsub(/\s+/, '_') }

      missing = normalized_required - normalized_headers
      if missing.any?
        errors << { row: 0, message: "Missing required columns: #{missing.join(', ')}" }
      end
    end

    def finalize_import
      summary = {
        total_rows: import_run.total_rows,
        created: import_run.created_count,
        updated: import_run.updated_count,
        skipped: import_run.skipped_count,
        errors: import_run.error_count
      }

      error_report = errors.any? ? { errors: errors } : {}

      if import_run.error_count > 0 && (import_run.created_count > 0 || import_run.updated_count > 0)
        import_run.partial!(summary: summary, error_report: error_report)
      elsif import_run.error_count > 0
        import_run.fail!(error_report: error_report)
      else
        import_run.succeed!(summary: summary)
      end
    end
  end
end
