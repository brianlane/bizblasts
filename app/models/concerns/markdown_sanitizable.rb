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
#   - Uses Sanitize gem with RELAXED configuration
#   - Allows safe HTML tags: p, br, strong, em, a, ul, ol, li, etc.
#   - Blocks script tags, event handlers, and dangerous protocols
#   - Sanitizes before validation to ensure clean data in database
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
  def sanitize_markdown_fields
    return if self.class._markdown_fields.blank?

    self.class._markdown_fields.each do |field|
      next unless respond_to?(field)
      next unless send("#{field}_changed?")

      value = send(field)
      next if value.blank?

      # Sanitize the markdown content
      sanitized = Sanitize.fragment(
        value,
        Sanitize::Config::RELAXED
      )

      # Update the field with sanitized content
      send("#{field}=", sanitized)
    end
  end
end
