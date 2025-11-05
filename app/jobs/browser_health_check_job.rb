# frozen_string_literal: true

# BrowserHealthCheckJob periodically verifies that Chrome/Chromium is available
# This helps detect browser availability issues before they impact users
# Schedule this job to run hourly for proactive monitoring
class BrowserHealthCheckJob < ApplicationJob
  queue_as :default

  # Don't retry - this is a health check, we want fresh results
  retry_on StandardError, wait: 1.hour, attempts: 1

  def perform
    Rails.logger.info '[BrowserHealthCheckJob] Starting browser health check'

    # Check if browser executable can be found
    browser_path = PlaceIdExtraction::BrowserPathResolver.resolve

    if browser_path
      Rails.logger.info "[BrowserHealthCheckJob] ✓ Browser found at: #{browser_path}"

      # Verify the file exists and is executable
      if File.exist?(browser_path) && File.executable?(browser_path)
        Rails.logger.info '[BrowserHealthCheckJob] ✓ Browser is executable'

        # Try to get version (quick test without launching full browser)
        version_output = check_browser_version(browser_path)

        if version_output
          Rails.logger.info "[BrowserHealthCheckJob] ✓ Browser version: #{version_output}"

          # Store healthy status in cache for monitoring
          store_health_status(
            healthy: true,
            browser_path: browser_path,
            version: version_output,
            message: 'Browser is available and functional'
          )
        else
          Rails.logger.warn '[BrowserHealthCheckJob] ⚠ Browser version check failed'
          store_health_status(
            healthy: false,
            browser_path: browser_path,
            message: 'Browser found but version check failed'
          )
        end
      else
        Rails.logger.error "[BrowserHealthCheckJob] ✗ Browser not executable: #{browser_path}"
        store_health_status(
          healthy: false,
          browser_path: browser_path,
          message: 'Browser found but not executable'
        )
      end
    else
      Rails.logger.warn '[BrowserHealthCheckJob] ⚠ No browser executable found'
      store_health_status(
        healthy: false,
        message: 'No browser executable found on system'
      )
    end

    # Check recent extraction metrics
    check_extraction_metrics

    Rails.logger.info '[BrowserHealthCheckJob] Health check completed'
  rescue StandardError => e
    Rails.logger.error "[BrowserHealthCheckJob] Health check failed: #{e.message}"
    Rails.logger.error "[BrowserHealthCheckJob] Backtrace: #{e.backtrace.first(3).join(', ')}"

    store_health_status(
      healthy: false,
      message: "Health check error: #{e.message}"
    )

    # Re-raise to mark job as failed for monitoring
    raise
  end

  private

  def check_browser_version(browser_path)
    require 'open3'

    # Quick version check with timeout - use Open3 to avoid shell injection
    output, status = Open3.capture2e(browser_path, '--version')

    # Return version if command succeeded and output looks valid
    return output.strip if status.success? && output.match?(/Chrome|Chromium/i)

    nil
  rescue StandardError => e
    Rails.logger.debug "[BrowserHealthCheckJob] Version check error: #{e.message}"
    nil
  end

  def store_health_status(healthy:, browser_path: nil, version: nil, message: nil)
    status = {
      healthy: healthy,
      checked_at: Time.current.iso8601,
      environment: Rails.env
    }

    status[:browser_path] = browser_path if browser_path
    status[:version] = version if version
    status[:message] = message if message

    # Store in cache for 2 hours (should run more frequently than this)
    Rails.cache.write('browser_health_check:status', status, expires_in: 2.hours)

    # Log status for external monitoring
    log_level = healthy ? :info : :warn
    Rails.logger.send(log_level, "[BrowserHealthCheckJob] Health status: #{status.to_json}")
  end

  def check_extraction_metrics
    # Check metrics from past 24 hours
    today = Date.current
    yesterday = Date.yesterday

    success_today = Rails.cache.read("place_id_extraction:metrics:success:#{today}") || 0
    success_yesterday = Rails.cache.read("place_id_extraction:metrics:success:#{yesterday}") || 0

    error_today = Rails.cache.read("place_id_extraction:metrics:error:#{today}") || 0
    error_yesterday = Rails.cache.read("place_id_extraction:metrics:error:#{yesterday}") || 0

    not_found_today = Rails.cache.read("place_id_extraction:metrics:not_found:#{today}") || 0
    not_found_yesterday = Rails.cache.read("place_id_extraction:metrics:not_found:#{yesterday}") || 0

    total_attempts = success_today + success_yesterday + error_today + error_yesterday + not_found_today + not_found_yesterday

    if total_attempts > 0
      success_rate = ((success_today + success_yesterday).to_f / total_attempts * 100).round(1)

      Rails.logger.info "[BrowserHealthCheckJob] Recent metrics (24h):"
      Rails.logger.info "  - Success: #{success_today + success_yesterday}"
      Rails.logger.info "  - Errors: #{error_today + error_yesterday}"
      Rails.logger.info "  - Not found: #{not_found_today + not_found_yesterday}"
      Rails.logger.info "  - Success rate: #{success_rate}%"

      # Warn if success rate is low
      if success_rate < 50 && total_attempts > 5
        Rails.logger.warn "[BrowserHealthCheckJob] ⚠ Low success rate detected: #{success_rate}%"
      end
    else
      Rails.logger.info '[BrowserHealthCheckJob] No recent extraction attempts'
    end
  end
end
