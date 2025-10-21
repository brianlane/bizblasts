# frozen_string_literal: true

# PlaceIdExtractionJob extracts Google Place ID from a Google Maps URL using headless browser
# This job runs asynchronously to avoid blocking the user request
# SECURITY: This job has rate limiting, circuit breaker, and resource limits to prevent abuse
class PlaceIdExtractionJob < ApplicationJob
  queue_as :default  # SECURITY: Isolation via MAX_CONCURRENT_JOBS limit instead of separate queue

  # Timeout after 30 seconds to prevent hung jobs
  EXTRACTION_TIMEOUT = 30.seconds

  # SECURITY: Circuit breaker - max concurrent jobs to prevent resource exhaustion
  MAX_CONCURRENT_JOBS = 3

  # SECURITY: Circuit breaker - disable extraction after repeated failures
  CIRCUIT_BREAKER_THRESHOLD = 10

  def perform(job_id, google_maps_url)
    # SECURITY: Sanitize URL in logs (truncate to prevent log injection)
    sanitized_url = google_maps_url[0..60] + "..."
    Rails.logger.info "[PlaceIdExtractionJob] Starting extraction for job_id: #{job_id}"
    Rails.logger.info "[PlaceIdExtractionJob] URL (truncated): #{sanitized_url}"

    # SECURITY: Circuit breaker - check recent failure rate
    recent_failures = Rails.cache.read('place_id_extraction:recent_failures') || 0
    if recent_failures >= CIRCUIT_BREAKER_THRESHOLD
      error_msg = 'Automatic extraction is temporarily unavailable due to repeated failures. Please use manual method.'
      Rails.logger.warn "[PlaceIdExtractionJob] Circuit breaker triggered: #{recent_failures} recent failures"
      store_status(job_id, status: 'failed', error: error_msg)
      return
    end

    # SECURITY: Check concurrent job limit to prevent resource exhaustion
    concurrent_jobs_count = count_concurrent_jobs
    if concurrent_jobs_count >= MAX_CONCURRENT_JOBS
      error_msg = 'System busy processing other extractions. Please try again in a few minutes.'
      Rails.logger.warn "[PlaceIdExtractionJob] Too many concurrent jobs: #{concurrent_jobs_count}"
      store_status(job_id, status: 'failed', error: error_msg)
      return
    end

    # Store initial status
    store_status(job_id, status: 'processing', message: 'Loading Google Maps...')

    # Extract Place ID using headless browser
    place_id = extract_place_id_from_maps(google_maps_url, job_id)

    if place_id
      # SECURITY: Reset failure counter on success
      Rails.cache.write('place_id_extraction:recent_failures', 0, expires_in: 1.hour)

      # Track success metric
      track_extraction_metric('success')

      Rails.logger.info "[PlaceIdExtractionJob] Successfully extracted Place ID: #{place_id}"
      store_status(job_id, status: 'completed', place_id: place_id, message: "Place ID found: #{place_id}")
    else
      # SECURITY: Increment failure counter (atomic operation)
      new_failures = Rails.cache.increment('place_id_extraction:recent_failures', 1, expires_in: 1.hour) || 1
      Rails.cache.write('place_id_extraction:recent_failures', 1, expires_in: 1.hour) if new_failures == 1

      # Track failure metric
      track_extraction_metric('not_found')

      Rails.logger.warn "[PlaceIdExtractionJob] Failed to extract Place ID from: #{sanitized_url}"
      store_status(job_id, status: 'failed', error: 'Could not find Place ID. Please use manual method.')
    end
  rescue StandardError => e
    # SECURITY: Increment failure counter on exception (atomic operation)
    new_failures = Rails.cache.increment('place_id_extraction:recent_failures', 1, expires_in: 1.hour) || 1
    Rails.cache.write('place_id_extraction:recent_failures', 1, expires_in: 1.hour) if new_failures == 1

    # Track error metric
    track_extraction_metric('error')

    Rails.logger.error "[PlaceIdExtractionJob] Error: #{e.message}"
    Rails.logger.error "[PlaceIdExtractionJob] Backtrace: #{e.backtrace.first(5).join(', ')}"
    store_status(job_id, status: 'failed', error: 'An error occurred during extraction. Please try again or use manual method.')
  end

  private

  def extract_place_id_from_maps(url, job_id)
    require 'capybara/cuprite'

    browser = nil
    browser_pid = nil

    begin
      # SECURITY: Configure Cuprite with resource limits
      browser = Capybara::Cuprite::Browser.new(
        headless: true,
        window_size: [1920, 1080],
        browser_options: {
          'no-sandbox': nil,
          'disable-dev-shm-usage': nil,   # Prevent /dev/shm issues
          'disable-gpu': nil,              # Reduce GPU usage
          'disable-extensions': nil,       # Disable extensions for security
          'disable-popup-blocking': nil,   # For clicking review button
          # SECURITY: Limit memory usage
          'js-flags': '--max-old-space-size=512'  # 512MB max
        },
        timeout: EXTRACTION_TIMEOUT,
        # SECURITY: Process timeout slightly longer than job timeout
        process_timeout: EXTRACTION_TIMEOUT + 5.seconds
      )

      # SECURITY: Track browser process ID for force kill if needed
      browser_pid = browser.process&.pid if browser.respond_to?(:process)
      Rails.logger.debug "[PlaceIdExtractionJob] Browser PID: #{browser_pid}"

      # Navigate to Google Maps URL
      browser.visit(url)
      store_status(job_id, status: 'processing', message: 'Page loaded, waiting for content to render...')

      # Wait for page to load (Google Maps is heavily JavaScript-based)
      # Wait up to 10 seconds for any button with "review" in aria-label to appear
      wait_start = Time.current
      max_wait = 10.seconds
      button_found = false

      while Time.current - wait_start < max_wait
        button_found = browser.evaluate(%{
          document.querySelector('button[aria-label*="eview"]') !== null ||
          document.querySelector('button[aria-label*="EVIEW"]') !== null ||
          document.querySelector('a[href*="review"]') !== null
        })
        break if button_found
        sleep 0.5
      end

      Rails.logger.info "[PlaceIdExtractionJob] Button found: #{button_found} after #{(Time.current - wait_start).round(1)}s"
      store_status(job_id, status: 'processing', message: 'Page rendered, searching for Place ID...')

      # Try multiple strategies to find the Place ID

      # Strategy 1: Look for Place ID in page source (after JavaScript renders)
      page_source = browser.body
      place_id = extract_place_id_from_html(page_source)
      return place_id if place_id

      store_status(job_id, status: 'processing', message: 'Trying to click review button...')

      # Strategy 2: Click "Write a review" button and extract from iframe
      place_id = extract_from_review_iframe(browser)
      return place_id if place_id

      # Strategy 3: Look in page metadata
      place_id = extract_from_metadata(browser)
      return place_id if place_id

      nil
    ensure
      # SECURITY: Aggressive cleanup to prevent browser process leaks
      if browser
        begin
          Rails.logger.debug "[PlaceIdExtractionJob] Attempting graceful browser shutdown..."
          browser.quit
          Rails.logger.debug "[PlaceIdExtractionJob] Browser quit successfully"
        rescue => e
          Rails.logger.error "[PlaceIdExtractionJob] Failed to quit browser gracefully: #{e.message}"

          # SECURITY: Force kill the browser process if graceful quit fails
          if browser_pid
            begin
              Rails.logger.warn "[PlaceIdExtractionJob] Force killing browser process: #{browser_pid}"
              Process.kill('KILL', browser_pid)
              Rails.logger.info "[PlaceIdExtractionJob] Browser process #{browser_pid} killed"
            rescue Errno::ESRCH
              Rails.logger.debug "[PlaceIdExtractionJob] Browser process #{browser_pid} already terminated"
            rescue => kill_error
              Rails.logger.error "[PlaceIdExtractionJob] Failed to kill browser process #{browser_pid}: #{kill_error.message}"
            end
          end
        end
      end
    end
  end

  def extract_place_id_from_html(html)
    # Look for Place ID patterns in the HTML
    # Place IDs start with ChIJ, GhIJ, E, or I
    # Scan ALL matches and return the first valid one
    html.scan(/["']([A-Z][a-zA-Z0-9_-]{20,})["']/).each do |match|
      candidate = match[0]
      return candidate if candidate =~ /^(ChIJ|GhIJ|E|I)/
    end
    nil
  end

  def extract_from_review_iframe(browser)
    # Try to find and click the "Write a review" button
    # Button text varies by language, so we'll try multiple selectors
    review_button_selectors = [
      'button[aria-label*="Write a review"]',
      'button[aria-label*="write a review"]',
      'button[aria-label*="WRITE A REVIEW"]',
      'button[aria-label*="Review"]',
      'button[aria-label*="review"]',
      'button[aria-label*="eview"]',
      'a[href*="review"]',
      'a[data-value="Write a review"]'
    ]

    review_button_selectors.each_with_index do |selector, index|
      begin
        # Check if element exists
        element_exists = browser.evaluate("document.querySelector('#{selector}') !== null")

        if element_exists
          Rails.logger.info "[PlaceIdExtractionJob] Found review button with selector #{index + 1}: #{selector}"

          # Try to click it
          browser.execute("document.querySelector('#{selector}').click()")

          # Wait for iframe to load (Google Maps can take 7-10 seconds)
          iframe_found = false
          15.times do |attempt|
            sleep 1
            iframe_count = browser.evaluate("document.querySelectorAll('iframe').length")
            if iframe_count && iframe_count > 0
              iframe_found = true
              Rails.logger.info "[PlaceIdExtractionJob] Found #{iframe_count} iframe(s) after #{attempt + 1} seconds"
              break
            end
          end

          # Look for iframe with Place ID in src
          iframes = browser.evaluate("Array.from(document.querySelectorAll('iframe')).map(f => f.src)")
          if iframes && iframes.any?
            Rails.logger.info "[PlaceIdExtractionJob] Checking #{iframes.length} iframe(s) for Place ID"
            iframes.each_with_index do |iframe_src, iframe_index|
              Rails.logger.debug "[PlaceIdExtractionJob] Iframe #{iframe_index + 1} src: #{iframe_src[0..100]}..."
              place_id = extract_place_id_from_url(iframe_src)
              if place_id
                Rails.logger.info "[PlaceIdExtractionJob] Found Place ID in iframe #{iframe_index + 1}: #{place_id}"
                return place_id
              end
            end
          else
            Rails.logger.warn "[PlaceIdExtractionJob] No iframes found after clicking button"
          end
        end
      rescue => e
        Rails.logger.warn "[PlaceIdExtractionJob] Review button strategy #{index + 1} failed: #{e.message}"
      end
    end

    Rails.logger.warn "[PlaceIdExtractionJob] All review button strategies failed"
    nil
  end

  def extract_from_metadata(browser)
    # Look for Place ID in meta tags or structured data
    meta_content = browser.evaluate(%{
      var placeId = null;
      document.querySelectorAll('meta').forEach(function(meta) {
        var content = meta.getAttribute('content') || '';
        if (content.match(/^(ChIJ|GhIJ|E|I)[a-zA-Z0-9_-]{20,}/)) {
          placeId = content;
        }
      });
      placeId;
    })

    return meta_content if meta_content && meta_content =~ /^(ChIJ|GhIJ|E|I)/

    nil
  end

  def extract_place_id_from_url(url)
    # Extract Place ID from a URL parameter or path
    # Scan ALL matches and return the first valid one
    url.scan(/([A-Z][a-zA-Z0-9_-]{20,})/).each do |match|
      candidate = match[0]
      return candidate if candidate =~ /^(ChIJ|GhIJ|E|I)/
    end
    nil
  end

  def store_status(job_id, status:, place_id: nil, message: nil, error: nil)
    data = {
      status: status,
      updated_at: Time.current.to_i
    }
    data[:place_id] = place_id if place_id
    data[:message] = message if message
    data[:error] = error if error

    # Store in Rails cache with 10 minute expiry
    Rails.cache.write("place_id_extraction:#{job_id}", data, expires_in: 10.minutes)
  end

  # SECURITY: Count concurrent extraction jobs to prevent resource exhaustion
  # Note: This uses Solid Queue's job table. For other queue backends, adjust accordingly.
  def count_concurrent_jobs
    begin
      # Count PlaceIdExtractionJob instances that haven't finished yet
      # Filter by class_name instead of queue_name to work regardless of queue
      if defined?(Solid::Queue::Job)
        Solid::Queue::Job.where(
          class_name: 'PlaceIdExtractionJob',
          finished_at: nil
        ).count
      else
        # Fallback for development/test or if Solid Queue isn't available
        0
      end
    rescue => e
      Rails.logger.error "[PlaceIdExtractionJob] Error counting concurrent jobs: #{e.message}"
      0  # Allow job to proceed on error
    end
  end

  # SECURITY: Track extraction metrics for monitoring
  # This helps identify if the feature is being abused or if Google is blocking us
  def track_extraction_metric(result_type)
    begin
      # Increment counter for this result type
      metric_key = "place_id_extraction:metrics:#{result_type}:#{Date.current}"
      Rails.cache.increment(metric_key, 1, expires_in: 7.days)
      Rails.cache.write(metric_key, 1, expires_in: 7.days) unless Rails.cache.read(metric_key)

      # Log metric for external monitoring systems
      Rails.logger.info "[PlaceIdExtractionJob] Metric: #{result_type}"
    rescue => e
      Rails.logger.error "[PlaceIdExtractionJob] Error tracking metric: #{e.message}"
      # Don't fail job if metrics fail
    end
  end
end
