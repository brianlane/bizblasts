# frozen_string_literal: true

module Csv
  class CustomersImporter < BaseImporter
    protected

    def required_headers
      %w[email first_name last_name]
    end

    def process_row(row, row_number)
      email = row['email']&.strip&.downcase

      if email.blank?
        add_error(row_number, 'Email is required')
        return
      end

      unless email.match?(URI::MailTo::EMAIL_REGEXP)
        add_error(row_number, "Invalid email format: #{email}")
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
        customer = business.tenant_customers.new(attributes)

        if customer.save
          import_run.increment_progress!(created: true)
        else
          add_error(row_number, "Create failed: #{customer.errors.full_messages.join(', ')}")
        end
      end
    end

    def find_existing_record(row)
      email = row['email']&.strip&.downcase
      business.tenant_customers.find_by('LOWER(email) = ?', email)
    end

    def build_attributes(row)
      attrs = {
        email: row['email']&.strip&.downcase,
        first_name: row['first_name']&.strip,
        last_name: row['last_name']&.strip
      }

      # Optional fields
      attrs[:phone] = row['phone']&.strip if row['phone'].present?
      attrs[:address] = row['address']&.strip if row['address'].present?
      attrs[:notes] = row['notes']&.strip if row['notes'].present?
      attrs[:active] = parse_boolean(row['active'], default: true) if row['active'].present?
      attrs[:phone_opt_in] = parse_boolean(row['phone_opt_in'], default: false) if row['phone_opt_in'].present?
      attrs[:email_marketing_opt_out] = parse_boolean(row['email_marketing_opt_out'], default: false) if row['email_marketing_opt_out'].present?

      attrs
    end
  end
end
