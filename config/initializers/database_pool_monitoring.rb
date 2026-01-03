# frozen_string_literal: true

# Database Connection Pool Monitoring
# Monitors connection pool usage and alerts on potential exhaustion
# This is critical for analytics queries which can hold connections for longer periods

Rails.application.config.after_initialize do
  # Only enable monitoring in production or if explicitly enabled
  next unless Rails.env.production? || ENV['ENABLE_DB_POOL_MONITORING'] == 'true'

  # Monitor connection pool usage periodically
  Thread.new do
    loop do
      begin
        # Wait 30 seconds between checks
        sleep 30

        pool = ActiveRecord::Base.connection_pool

        # Get pool statistics
        pool_size = pool.size
        active_connections = pool.connections.count(&:in_use?)
        available_connections = pool_size - active_connections
        utilization_percent = (active_connections.to_f / pool_size * 100).round(2)

        # Log pool status at debug level
        Rails.logger.debug(
          "[DB Pool] Size: #{pool_size}, " \
          "Active: #{active_connections}, " \
          "Available: #{available_connections}, " \
          "Utilization: #{utilization_percent}%"
        )

        # Warn if pool is getting full (>80% utilization)
        if utilization_percent > 80
          Rails.logger.warn(
            "[DB Pool] High utilization: #{utilization_percent}% " \
            "(#{active_connections}/#{pool_size} connections in use)"
          )

          # Emit notification for monitoring/alerting
          ActiveSupport::Notifications.instrument(
            'database.connection_pool.high_utilization',
            pool_size: pool_size,
            active: active_connections,
            utilization: utilization_percent
          )
        end

        # Critical alert if pool is nearly exhausted (>95% utilization)
        if utilization_percent > 95
          Rails.logger.error(
            "[DB Pool] CRITICAL: Pool nearly exhausted: #{utilization_percent}% " \
            "(#{active_connections}/#{pool_size} connections in use)"
          )

          # Send critical alert to monitoring system
          ActiveSupport::Notifications.instrument(
            'database.connection_pool.critical',
            pool_size: pool_size,
            active: active_connections,
            utilization: utilization_percent
          )

          # If Sentry is available, capture the issue
          if defined?(Sentry)
            Sentry.capture_message(
              'Database connection pool nearly exhausted',
              level: :error,
              extra: {
                pool_size: pool_size,
                active_connections: active_connections,
                utilization_percent: utilization_percent
              }
            )
          end
        end

      rescue StandardError => e
        Rails.logger.error "[DB Pool Monitor] Error: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
      end
    end
  end

  # Subscribe to connection checkout/checkin for detailed tracking
  ActiveSupport::Notifications.subscribe('checkout.active_record') do |name, start, finish, id, payload|
    duration = (finish - start) * 1000 # Convert to milliseconds

    # Warn if connection checkout took too long (potential pool exhaustion)
    if duration > 1000 # 1 second
      Rails.logger.warn(
        "[DB Pool] Slow connection checkout: #{duration.round(2)}ms " \
        "(potential pool contention)"
      )

      ActiveSupport::Notifications.instrument(
        'database.connection_pool.slow_checkout',
        duration_ms: duration
      )
    end
  end

  # Monitor connection pool statistics on a schedule
  ActiveSupport::Notifications.subscribe('database.connection_pool.high_utilization') do |name, start, finish, id, payload|
    # Log to structured logging system if available
    if defined?(Rails.logger.tagged)
      Rails.logger.tagged('DB_POOL_WARNING') do
        Rails.logger.warn(
          "Connection pool high utilization: #{payload[:utilization]}% " \
          "(#{payload[:active]}/#{payload[:pool_size]})"
        )
      end
    end
  end

  ActiveSupport::Notifications.subscribe('database.connection_pool.critical') do |name, start, finish, id, payload|
    if defined?(Rails.logger.tagged)
      Rails.logger.tagged('DB_POOL_CRITICAL') do
        Rails.logger.error(
          "CRITICAL: Connection pool nearly exhausted: #{payload[:utilization]}% " \
          "(#{payload[:active]}/#{payload[:pool_size]})"
        )
      end
    end
  end

  Rails.logger.info '[DB Pool Monitor] Connection pool monitoring started'
end

# Add helper method to check pool status
module DatabasePoolHelper
  def self.pool_status
    pool = ActiveRecord::Base.connection_pool
    {
      size: pool.size,
      active: pool.connections.count(&:in_use?),
      available: pool.size - pool.connections.count(&:in_use?),
      utilization: (pool.connections.count(&:in_use?).to_f / pool.size * 100).round(2)
    }
  end

  def self.log_pool_status
    status = pool_status
    Rails.logger.info(
      "[DB Pool Status] Size: #{status[:size]}, " \
      "Active: #{status[:active]}, " \
      "Available: #{status[:available]}, " \
      "Utilization: #{status[:utilization]}%"
    )
    status
  end
end
