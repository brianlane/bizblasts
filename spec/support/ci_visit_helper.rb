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
      # In CI, catch pending connection errors and timeouts, then verify if page actually loaded
      begin
        super(path)
      rescue Ferrum::PendingConnectionsError, Ferrum::TimeoutError => e
        # Log the error and verify if navigation actually succeeded
        warn "[CI Visit Helper] #{e.class.name} for #{path}, verifying navigation..."
        
        # Get current URL from browser
        current_url = page.driver.browser.current_url rescue nil
        
        # Build expected URL for comparison
        expected_url = if path.start_with?('http')
          path
        else
          # For relative paths, use Capybara.app_host + path
          "#{Capybara.app_host}#{path}"
        end
        
        # Normalize both URLs for comparison:
        # 1. Remove query strings and fragments
        # 2. Remove trailing slashes
        # 3. Parse into URI to compare host, port, and path components separately
        begin
          expected_uri = URI.parse(expected_url.split('?').first.split('#').first.chomp('/'))
          current_uri = URI.parse(current_url.split('?').first.split('#').first.chomp('/')) if current_url
          
          # Compare host, path, and port (accounting for default ports)
          urls_match = current_uri &&
                      current_uri.host == expected_uri.host &&
                      current_uri.path == expected_uri.path &&
                      (current_uri.port == expected_uri.port || 
                       (expected_uri.port.nil? && current_uri.port == 80) ||
                       (expected_uri.port.nil? && current_uri.port == 3000))  # Common Rails dev port
        rescue URI::InvalidURIError => uri_error
          warn "[CI Visit Helper] URI parsing error: #{uri_error.message}"
          urls_match = false
        end
        
        if urls_match
          # URL matches (host, path, and normalized port) - verify the page rendered
          if page.has_css?('body', wait: 2)
            warn "[CI Visit Helper] Navigation succeeded to #{current_url}, continuing despite pending connections"
            # Give JS a moment to initialize
            sleep 0.3
          else
            warn "[CI Visit Helper] URL correct but no body element found, re-raising error"
            raise e
          end
        else
          # Navigation failed - URL didn't change to expected target
          warn "[CI Visit Helper] Navigation failed - expected: #{expected_url}, got: #{current_url}"
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

