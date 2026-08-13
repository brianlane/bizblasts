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
  # Override visit to handle pending connection errors more gracefully
  # This applies to both CI and local environments since Ferrum 0.17.1 raises these errors
  # despite pending_connection_errors: false setting (see capybara.rb comment)
  # Report the timeouts actually in force when a browser-startup timeout fires.
  #
  # spec/support/capybara.rb registers :cuprite with process_timeout: 240 in CI,
  # yet CI has reported "Browser did not produce websocket url within 10 seconds"
  # -- and 10 is Ferrum's built-in default, which it only falls back to when
  # :process_timeout is absent from its options. Something is bypassing the tuned
  # registration and we have not been able to reproduce it locally: loading
  # spec/support/capybara.rb outside CI yields 240, cuprite's own bare
  # auto-registration (capybara/cuprite.rb:14) is the only other registration in
  # play, and Capybara.reset! is just an alias for reset_sessions! so it does not
  # clear registrations.
  #
  # This logs the evidence needed to settle it the next time it happens. Never
  # raises -- diagnostics must not mask the original failure.
  def log_ferrum_timeout_diagnostics(error)
    driver = page.driver
    opts   = driver.respond_to?(:options) ? driver.options : {}
    warn "[Visit Helper][diag] #{error.class}: #{error.message}"
    warn "[Visit Helper][diag] Capybara.current_driver=#{Capybara.current_driver.inspect} " \
         "driver=#{driver.class}"
    warn "[Visit Helper][diag] driver options: process_timeout=#{opts[:process_timeout].inspect} " \
         "timeout=#{opts[:timeout].inspect} (process_timeout key present? #{opts.key?(:process_timeout)})"
    warn "[Visit Helper][diag] Ferrum defaults: PROCESS_TIMEOUT=" \
         "#{Ferrum::Browser::Options::PROCESS_TIMEOUT} DEFAULT_TIMEOUT=" \
         "#{Ferrum::Browser::Options::DEFAULT_TIMEOUT}"
    warn "[Visit Helper][diag] ENV: CI=#{ENV['CI'].inspect} " \
         "FERRUM_PROCESS_TIMEOUT=#{ENV['FERRUM_PROCESS_TIMEOUT'].inspect} " \
         "FERRUM_TIMEOUT=#{ENV['FERRUM_TIMEOUT'].inspect}"
  rescue StandardError => diag_error
    warn "[Visit Helper][diag] diagnostics unavailable: #{diag_error.class}: #{diag_error.message}"
  end

  def visit(path)
    begin
      super(path)
    rescue Ferrum::PendingConnectionsError, Ferrum::TimeoutError, Ferrum::ProcessTimeoutError => e
      log_ferrum_timeout_diagnostics(e) if e.is_a?(Ferrum::ProcessTimeoutError)

      if e.is_a?(Ferrum::ProcessTimeoutError) && !Thread.current[:visit_retrying]
        Thread.current[:visit_retrying] = true
        warn "[Visit Helper] Process timeout starting browser, resetting session and retrying..."
        Capybara.reset!
        sleep 1
        return visit(path)
      end

      # Log the error and verify if navigation actually succeeded
      log_prefix = ENV['CI'] == 'true' ? "[CI Visit Helper]" : "[Visit Helper]"
      warn "#{log_prefix} #{e.class.name} for #{path}, verifying navigation..."

      # Get current URL from browser (use Capybara's API for reliability)
      current_url = page.current_url rescue nil

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

        # Compare host + path (ignore port differences between app_host and Capybara server)
        urls_match = current_uri &&
                    current_uri.host == expected_uri.host &&
                    current_uri.path == expected_uri.path
      rescue URI::InvalidURIError => uri_error
        warn "#{log_prefix} URI parsing error: #{uri_error.message} (expected: #{expected_url.inspect}, current: #{current_url.inspect})"
        urls_match = false
      end

      debug_message = "#{log_prefix} expected_url=#{expected_url}, current_url=#{current_url}, urls_match=#{urls_match}"
      warn debug_message

      if urls_match
        # URL matches (host, path, and normalized port) - verify the page rendered
        begin
          if page.has_css?('body', wait: 2)
            warn "#{log_prefix} Navigation succeeded to #{current_url}, continuing despite pending connections"
            # Give JS a moment to initialize
            sleep 0.3
          else
            warn "#{log_prefix} URL correct but no body element found, re-raising error"
            raise e
          end
        rescue Ferrum::NodeNotFoundError, Ferrum::BrowserError => body_check_error
          warn "#{log_prefix} Body check failed (#{body_check_error.class}), re-raising original error"
          raise e
        end
      else
        # URL doesn't match - check if this is a redirect (which is a successful navigation)
        begin
          if current_url && page.has_css?('body', wait: 2)
            warn "#{log_prefix} Navigation succeeded with redirect from #{expected_url} to #{current_url}"
            # This is likely a successful POST that redirected - accept it
            sleep 0.3
          else
            # Navigation failed - attempt a single forced navigation without waiting for network idle
            warn "#{log_prefix} Navigation mismatch detected, attempting forced navigation to #{expected_url}"
            begin
              page.driver.browser.goto(expected_url)
              if page.has_css?('body', wait: 5)
                warn "#{log_prefix} Forced navigation succeeded for #{expected_url}"
                sleep 0.3
              else
                warn "#{log_prefix} Forced navigation loaded URL but no body found, raising original error"
                raise e
              end
            rescue => forced_error
              warn "#{log_prefix} Forced navigation failed: #{forced_error.class} - #{forced_error.message}"
              raise e
            end
          end
        rescue Ferrum::NodeNotFoundError, Ferrum::BrowserError => body_check_error
          warn "#{log_prefix} Body check failed (#{body_check_error.class}), re-raising original error"
          raise e
        end
      end
    ensure
      Thread.current[:visit_retrying] = false
    end
  end
end

RSpec.configure do |config|
  config.include CIVisitHelper, type: :system
end

