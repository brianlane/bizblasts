# frozen_string_literal: true

module Csv
  class ServicesImporter < BaseImporter
    protected

    def required_headers
      %w[name price duration]
    end

    def process_row(row, row_number)
      name = row['name']&.strip

      if name.blank?
        add_error(row_number, 'Name is required')
        return
      end

      price = parse_decimal(row['price'])
      if price.nil? || price < 0
        add_error(row_number, "Invalid price: #{row['price']}")
        return
      end

      duration = parse_integer(row['duration'] || row['duration_(minutes)'])
      if duration.nil? || duration <= 0
        add_error(row_number, "Invalid duration: #{row['duration'] || row['duration_(minutes)']}")
        return
      end

      existing = find_existing_record(row)
      attributes = build_attributes(row)

      if existing
        if existing.update(attributes)
          import_run.increment_progress!(updated: true)
        else
          add_error(row_number, "Update failed: #{existing.errors.full_messages.join(', ')}")
        end
      else
        service = business.services.new(attributes)

        if service.save
          import_run.increment_progress!(created: true)
        else
          add_error(row_number, "Create failed: #{service.errors.full_messages.join(', ')}")
        end
      end
    end

    def find_existing_record(row)
      name = row['name']&.strip
      business.services.find_by('LOWER(name) = ?', name.downcase)
    end

    def build_attributes(row)
      attrs = {
        name: row['name']&.strip,
        price: parse_decimal(row['price']),
        duration: parse_integer(row['duration'] || row['duration_(minutes)'])
      }

      # Optional fields
      attrs[:description] = row['description']&.strip if row['description'].present?
      attrs[:active] = parse_boolean(row['active'], default: true) if row['active'].present?
      attrs[:featured] = parse_boolean(row['featured'], default: false) if row['featured'].present?
      attrs[:tips_enabled] = parse_boolean(row['tips_enabled'], default: false) if row['tips_enabled'].present?

      if row['service_type'].present?
        service_type = row['service_type'].to_s.strip.downcase
        attrs[:service_type] = service_type if Service.service_types.key?(service_type)
      end

      attrs
    end
  end
end
