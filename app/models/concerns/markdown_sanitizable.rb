# frozen_string_literal: true

# Markdown Sanitization Concern
#
# This concern provides server-side HTML sanitization for markdown fields.
# It works in conjunction with client-side XSS protection in the markdown editor.
#
# Usage:
#   class Article < ApplicationRecord
#     include MarkdownSanitizable
#     markdown_fields :content, :description
#   end
#
# Configuration:
#   - Uses custom Sanitize::Config::MARKDOWN configuration
#   - Configuration defined in: config/initializers/sanitize.rb
#   - Allows safe HTML tags: p, br, strong, em, a, ul, ol, li, tables, etc.
#   - Blocks script tags, event handlers, and dangerous protocols
#   - Sanitizes before validation to ensure clean data in database
#   - Automatically adds rel="noopener noreferrer" to external links
#
module MarkdownSanitizable
  extend ActiveSupport::Concern

  included do
    class_attribute :_markdown_fields, instance_writer: false, default: []
    before_validation :sanitize_markdown_fields
  end

  class_methods do
    # Declare which fields contain markdown content
    # @param fields [Array<Symbol>] Field names to sanitize
    def markdown_fields(*fields)
      self._markdown_fields = fields.map(&:to_s)
    end
  end

  private

  # Sanitize all declared markdown fields before validation
  # Uses Rails 7+ public Dirty API for Rails 8 compatibility
  def sanitize_markdown_fields
    return if self.class._markdown_fields.blank?

    self.class._markdown_fields.each do |field|
      next unless respond_to?(field)
      # Rails 8 compatible: use attribute_changed? instead of #{field}_changed?
      next unless attribute_changed?(field.to_sym)

      value = send(field)
      next if value.blank?

      # Sanitize the markdown content using our custom config
      # Configuration defined in config/initializers/sanitize.rb
      sanitized = Sanitize.fragment(
        value,
        Sanitize::Config::MARKDOWN
      )

      # Update the field with sanitized content
      send("#{field}=", sanitized)
    end
  end
end
