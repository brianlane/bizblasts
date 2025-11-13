# frozen_string_literal: true

# CI-specific helper to handle Ferrum::PendingConnectionsError
#
# IMPORTANT: Despite `pending_connection_errors: false` being set in capybara.rb,
# Ferrum 0.17.1 still raises PendingConnectionsError in CI when the timeout is reached
# before all network connections complete. This appears to be either:
# 1. A bug/limitation in Ferrum where timeout fires before the setting takes effect, OR
# 2. The setting only suppresses the check but not the timeout-triggered error
#
# Empirical evidence from CI runs shows this exception IS raised despite the setting,
# so this helper is necessary (not dead code).
#
# In CI environments (GitHub Actions), pages sometimes timeout waiting for all
# network connections to complete, even though the page has rendered successfully.
# This typically happens with:
# - Slow asset compilation on first page load
# - External resources (fonts, analytics, etc.) taking too long
# - CI environment resource constraints
# - Complex JavaScript initialization (e.g., page builder, rich editors)
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

