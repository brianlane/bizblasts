# frozen_string_literal: true

module Csv
  class ServicesExporter < BaseExporter
    protected

    def headers
      [
        'ID', 'Name', 'Description', 'Price', 'Duration (minutes)',
        'Active', 'Service Type', 'Featured', 'Tips Enabled', 'Created At'
      ]
    end

    def row_for(service)
      [
        service.id,
        service.name,
        service.description,
        format_currency(service.price),
        service.duration,
        format_boolean(service.active),
        service.service_type,
        format_boolean(service.featured),
        format_boolean(service.tips_enabled),
        format_datetime(service.created_at)
      ]
    end

    def sample_row
      [
        '', 'Service Name', 'Service description', '50.00', '60',
        'true', 'standard', 'false', 'true', ''
      ]
    end

    def default_records
      business.services.order(:name)
    end

    def export_name
      'services'
    end
  end
end
