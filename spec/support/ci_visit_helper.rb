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
# loaded by checking both the URL and DOM state. If the page navigated successfully,
# we continue with the test since the timeout was only for slow-loading resources.
#
module CIVisitHelper
  # Override visit to handle pending connection errors more gracefully in CI
  def visit(path)
    if ENV['CI'] == 'true'
      # Store the expected URL to verify navigation
      expected_path = path.start_with?('http') ? path : "#{Capybara.app_host}#{path}"
      
      # In CI, catch pending connection errors and verify if page actually loaded
      begin
        super(path)
      rescue Ferrum::PendingConnectionsError => e
        # Log the error and verify if navigation actually succeeded
        warn "[CI Visit Helper] PendingConnectionsError for #{path}, verifying navigation..."
        
        # Check if the browser actually navigated to the target URL
        # This prevents false positives where we check the old page's body
        current_url = page.driver.browser.current_url rescue nil
        
        if current_url && current_url.include?(path.split('?').first)
          # URL changed to target - now verify the page rendered
          if page.has_css?('body', wait: 2)
            warn "[CI Visit Helper] Navigation succeeded, page body detected despite pending connections"
            # Give JS a moment to initialize
            sleep 0.3
          else
            warn "[CI Visit Helper] URL changed but no body element, re-raising error"
            raise e
          end
        else
          # Navigation failed - URL didn't change
          warn "[CI Visit Helper] Navigation failed (URL: #{current_url}), re-raising error"
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

