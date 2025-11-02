# frozen_string_literal: true

# Markdown Preview Security Concern
#
# This concern adds stricter Content Security Policy headers for pages
# that use the markdown editor with live preview functionality.
#
# Security measures:
# - Blocks external script loading
# - Prevents inline event handlers (onclick, onerror, etc.)
# - Allows safe inline styles for markdown rendering
# - Uses nonces for trusted scripts
#
# Usage:
#   class Admin::ArticlesController < ApplicationController
#     include MarkdownPreviewSecurity
#     before_action :set_markdown_preview_csp, only: [:new, :edit]
#   end
#
module MarkdownPreviewSecurity
  extend ActiveSupport::Concern

  private

  # Set stricter CSP headers for markdown preview pages
  def set_markdown_preview_csp
    # Generate a nonce for this request
    @csp_nonce = SecureRandom.base64(16)

    # Set CSP headers with markdown preview security policy
    response.headers['Content-Security-Policy'] = build_markdown_preview_csp(@csp_nonce)
  end

  # Build CSP policy string for markdown preview
  def build_markdown_preview_csp(nonce)
    directives = [
      "default-src 'self'",
      "script-src 'self' 'nonce-#{nonce}' https://app.termly.io", # Allow only nonce-protected scripts
      "style-src 'self' 'unsafe-inline'", # Allow inline styles for markdown rendering
      "img-src 'self' https: data: blob:", # Allow images from various sources
      "font-src 'self' https: data:",
      "connect-src 'self' https: wss: ws:",
      "frame-src 'self' https://app.termly.io",
      "media-src 'self' https: data: blob:",
      "object-src 'none'", # Block object/embed tags
      "base-uri 'self'" # Prevent base tag injection
    ]

    directives.join('; ')
  end

  # Helper to get CSP nonce for view templates
  def csp_nonce
    @csp_nonce
  end
end
