# frozen_string_literal: true

require 'csv'

module Csv
  class BaseExporter
    attr_reader :business, :records

    def initialize(business:, records: nil)
      @business = business
      @records = records || default_records
    end

    def export
      CSV.generate(headers: true) do |csv|
        csv << headers
        records.find_each do |record|
          csv << row_for(record)
        end
      end
    end

    def template
      CSV.generate(headers: true) do |csv|
        csv << headers
        csv << sample_row if respond_to?(:sample_row, true)
      end
    end

    def filename
      "#{export_name}-#{business.name.parameterize}-#{Date.current}.csv"
    end

    protected

    def headers
      raise NotImplementedError, "Subclasses must implement #headers"
    end

    def row_for(record)
      raise NotImplementedError, "Subclasses must implement #row_for"
    end

    def default_records
      raise NotImplementedError, "Subclasses must implement #default_records"
    end

    def export_name
      raise NotImplementedError, "Subclasses must implement #export_name"
    end

    def format_datetime(datetime)
      datetime&.iso8601
    end

    def format_date(date)
      date&.strftime('%Y-%m-%d')
    end

    def format_boolean(value)
      value ? 'true' : 'false'
    end

    def format_currency(amount)
      amount&.to_f&.round(2)
    end
  end
end
