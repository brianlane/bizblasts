# Shared parsing logic for price and duration fields
# Used by Service, ServiceVariant, Product, and ProductVariant models
module PriceDurationParser
  extend ActiveSupport::Concern

  module ClassMethods
    def price_parser(attribute_name = :price)
      define_method "#{attribute_name}=" do |value|
        if value.is_a?(String) && value.present?
          # Accept patterns like: "$60", "60", "$60.25", " 60.25 ", etc.
          # Disallow negative prices entirely.
          cleaned = value.strip
          if cleaned.match?(/\A\$?\s*\d+(?:\.\d+)?\s*\z/)
            parsed_float = cleaned.delete_prefix('$').strip.to_f.round(2)
            instance_variable_set("@invalid_#{attribute_name}_input", nil)
            super(parsed_float)
          else
            # Store invalid input for validation and set attribute to nil to trigger validation
            instance_variable_set("@invalid_#{attribute_name}_input", value)
            super(nil)
          end
        elsif value.nil?
          # Allow nil to be set for presence validation
          instance_variable_set("@invalid_#{attribute_name}_input", nil)
          super(nil)
        elsif value.is_a?(String) && value.blank?
          # For blank strings, treat as nil for validation
          instance_variable_set("@invalid_#{attribute_name}_input", value)
          super(nil)
        else
          instance_variable_set("@invalid_#{attribute_name}_input", nil)
          super(value)
        end
      end

      define_method "#{attribute_name}_format_valid" do
        invalid_input = instance_variable_get("@invalid_#{attribute_name}_input")
        return unless invalid_input

        # Only add custom format error for non-blank invalid input
        # Rails presence validation already handles blank values with "can't be blank"
        unless invalid_input.blank?
          errors.add(attribute_name, "must be a valid number - '#{invalid_input}' is not a valid price format (e.g., '10.50' or '$10.50')")
        end
      end
    end

    def duration_parser(attribute_name = :duration)
      define_method "#{attribute_name}=" do |value|
        if value.is_a?(String)
          # Extract the first numeric substring, allowing optional decimals (e.g., "60.5 min" -> "60.5")
          match = value.match(/(\d+(?:\.\d+)?)/)
          parsed_value = if match
            # Round any decimal value to the nearest whole minute
            match[1].to_f.round
          else
            0
          end
          super(parsed_value > 0 ? parsed_value : nil)
        else
          super(value)
        end
      end
    end
  end
end
