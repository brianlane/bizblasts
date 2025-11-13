# frozen_string_literal: true

# CI-specific helper to handle Ferrum::PendingConnectionsError
#
# In CI environments (GitHub Actions), pages sometimes timeout waiting for all
# network connections to complete, even though the page has rendered successfully.
# This typically happens with:
# - Slow asset compilation on first page load
# - External resources (fonts, analytics, etc.) taking too long
# - CI environment resource constraints
#
# This helper catches PendingConnectionsError and verifies if the page actually
# loaded (by checking for <body> element). If the page is present, we continue
# with the test since the timeout was only for slow-loading resources that don't
# affect test execution.
#
module CIVisitHelper
  # Override visit to handle pending connection errors more gracefully in CI
  def visit(path)
    if ENV['CI'] == 'true'
      # In CI, catch pending connection errors and continue anyway if page rendered
      begin
        super(path)
      rescue Ferrum::PendingConnectionsError => e
        # Log the error but check if the page actually loaded
        warn "[CI Visit Helper] PendingConnectionsError for #{path}, checking if page loaded..."
        
        # Check if the page body is present - if so, the page loaded successfully
        # despite pending connections (likely slow-loading assets)
        if page.has_css?('body', wait: 2)
          warn "[CI Visit Helper] Page body detected, continuing despite pending connections"
          # Give JS a moment to initialize
          sleep 0.3
        else
          # Page really didn't load, re-raise the error
          warn "[CI Visit Helper] Page did not load, re-raising error"
          raise e
        end
      end
    else
      super(path)
    end
  end
end

RSpec.configure do |config|
  config.include CIVisitHelper, type: :system
end

