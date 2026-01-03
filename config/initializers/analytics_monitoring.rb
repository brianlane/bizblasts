# frozen_string_literal: true

# Analytics monitoring and alerting setup
# Subscribes to analytics events and sends alerts for slow queries and errors

if Rails.application.config.analytics&.enabled
  # Monitor slow analytics queries
  ActiveSupport::Notifications.subscribe('analytics.slow_query') do |name, start, finish, id, payload|
    duration = finish - start

    # Log slow query
    Rails.logger.warn "[Analytics] Slow query: #{payload[:query_name]} took #{duration.round(2)}s"

    # Alert to error tracking service if very slow (>2 seconds)
    if duration > 2.0 && defined?(Sentry)
      Sentry.capture_message(
        "Slow analytics query: #{payload[:query_name]}",
        level: :warning,
        extra: {
          duration: duration.round(2),
          query_name: payload[:query_name],
          business_id: payload[:business_id],
          threshold: payload[:threshold]
        }
      )
    end
  end

  # Monitor analytics job failures
  ActiveSupport::Notifications.subscribe('analytics.job_failed') do |name, start, finish, id, payload|
    Rails.logger.error "[Analytics] Job failed: #{payload[:job_name]}"
    Rails.logger.error "[Analytics] Error: #{payload[:error]}"

    # Send to error tracking
    if defined?(Sentry)
      Sentry.capture_exception(
        payload[:exception] || StandardError.new(payload[:error]),
        extra: {
          job_name: payload[:job_name],
          business_id: payload[:business_id]
        }
      )
    end
  end

  # Monitor analytics job performance
  ActiveSupport::Notifications.subscribe('analytics.job_complete') do |name, start, finish, id, payload|
    duration = finish - start

    Rails.logger.info "[Analytics] #{payload[:job_name]} completed in #{duration.round(2)}s"

    # Alert if job took too long
    if payload[:max_duration] && duration > payload[:max_duration]
      Rails.logger.error "[Analytics] #{payload[:job_name]} exceeded max duration (#{duration.round(2)}s > #{payload[:max_duration]}s)"

      if defined?(Sentry)
        Sentry.capture_message(
          "Analytics job exceeded duration threshold",
          level: :error,
          extra: {
            job_name: payload[:job_name],
            duration: duration.round(2),
            max_duration: payload[:max_duration],
            business_count: payload[:business_count],
            error_count: payload[:error_count]
          }
        )
      end
    end
  end

  # Monitor rate limiting
  ActiveSupport::Notifications.subscribe('analytics.rate_limited') do |name, start, finish, id, payload|
    Rails.logger.warn "[Analytics] Rate limit hit for IP: #{payload[:ip]}"

    # Track rate limiting frequency - alert if too many rate limits
    cache_key = "analytics_rate_limit_count:#{Date.current}"
    count = Rails.cache.increment(cache_key, 1, expires_in: 1.day)

    if count && count > 1000 # More than 1000 rate limits per day
      Rails.logger.error "[Analytics] High rate limit frequency: #{count} limits today"
    end
  end

  Rails.logger.info "[Analytics] Monitoring initialized"
end
