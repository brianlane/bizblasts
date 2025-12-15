# frozen_string_literal: true

module Csv
  class ProductsImporter < BaseImporter
    protected

    def required_headers
      %w[name price]
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

      existing = find_existing_record(row)
      attributes = build_attributes(row)

      if existing
        if existing.update(attributes)
          import_run.increment_progress!(updated: true)
        else
          add_error(row_number, "Update failed: #{existing.errors.full_messages.join(', ')}")
        end
      else
        product = business.products.new(attributes)

        if product.save
          import_run.increment_progress!(created: true)
        else
          add_error(row_number, "Create failed: #{product.errors.full_messages.join(', ')}")
        end
      end
    end

    def find_existing_record(row)
      name = row['name']&.strip
      business.products.find_by('LOWER(name) = ?', name.downcase)
    end

    def build_attributes(row)
      attrs = {
        name: row['name']&.strip,
        price: parse_decimal(row['price'])
      }

      # Optional fields
      attrs[:description] = row['description']&.strip if row['description'].present?
      attrs[:stock_quantity] = parse_integer(row['stock_quantity']) if row['stock_quantity'].present?
      attrs[:active] = parse_boolean(row['active'], default: true) if row['active'].present?
      attrs[:featured] = parse_boolean(row['featured'], default: false) if row['featured'].present?
      attrs[:tips_enabled] = parse_boolean(row['tips_enabled'], default: false) if row['tips_enabled'].present?

      if row['product_type'].present?
        product_type = row['product_type'].to_s.strip.downcase
        attrs[:product_type] = product_type if Product.product_types.key?(product_type)
      end

      attrs
    end
  end
end
