# frozen_string_literal: true

# CssSanitizer provides methods to sanitize CSS property names and values
# to prevent XSS attacks via CSS injection.
#
# This module can be used as:
#   1. Module methods: CssSanitizer.sanitize_css_value(value)
#   2. Included methods: include CssSanitizer; sanitize_css_value(value)
#
# Security Features:
# - Removes dangerous characters that could break out of CSS context
# - Removes dangerous CSS patterns (javascript:, expression(), etc.)
# - Uses loop-based sanitization to handle overlapping patterns
# - Limits length to prevent DoS attacks
module CssSanitizer
  module_function

  # Sanitize CSS property values to prevent XSS injection attacks
  #
  # @param value [String, nil] The CSS value to sanitize
  # @return [String] The sanitized CSS value
  #
  # @example
  #   CssSanitizer.sanitize_css_value('#ff0000')
  #   #=> '#ff0000'
  #
  #   CssSanitizer.sanitize_css_value('<script>alert("xss")</script>')
  #   #=> 'scriptalert("xss")/script'
  #
  #   CssSanitizer.sanitize_css_value('javascript:alert(1)')
  #   #=> 'alert(1)'
  def sanitize_css_value(value)
    return '' if value.blank?

    # Convert to string and strip whitespace
    value = value.to_s.strip

    # Remove any characters that could break out of CSS context
    # This prevents: }; </style><script> type attacks
    dangerous_chars = ['<', '>', '{', '}', '\\', '"', "'"]
    dangerous_chars.each do |char|
      value = value.gsub(char, '')
    end

    # Remove dangerous CSS patterns completely (repeat until stable)
    # This handles overlapping patterns like "ononerrorerror" or "expresexpression(sion("
    dangerous_patterns = [
      /javascript:/i,
      /expression\s*\(/i,
      /behavior\s*:/i,
      /vbscript:/i,
      /@import/i,
      /onload/i,
      /onerror/i
    ]

    dangerous_patterns.each do |pattern|
      loop do
        before = value
        value = value.gsub(pattern, '')
        break if before == value
      end
    end

    # Limit length to prevent DOS (return first 500 characters)
    value[0, 500]
  end

  # Sanitize CSS property names to prevent injection
  #
  # @param name [String, nil] The CSS property name to sanitize
  # @return [String] The sanitized CSS property name
  #
  # @example
  #   CssSanitizer.sanitize_css_property_name('color')
  #   #=> 'color'
  #
  #   CssSanitizer.sanitize_css_property_name('font_size')
  #   #=> 'font-size'
  #
  #   CssSanitizer.sanitize_css_property_name('bad<script>name')
  #   #=> 'badscriptname'
  def sanitize_css_property_name(name)
    return '' if name.blank?

    # Only allow alphanumeric, hyphens, and underscores
    # Convert underscores to hyphens for CSS convention
    name.to_s.gsub(/[^a-zA-Z0-9\-_]/, '').gsub('_', '-')
  end
end
