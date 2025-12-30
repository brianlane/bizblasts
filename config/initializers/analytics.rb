# frozen_string_literal: true

# Analytics system configuration
Rails.application.config.analytics = ActiveSupport::OrderedOptions.new

# Query performance monitoring
Rails.application.config.analytics.query_threshold = ENV.fetch('ANALYTICS_QUERY_THRESHOLD', '1.0').to_f
Rails.application.config.analytics.dashboard_query_threshold = ENV.fetch('ANALYTICS_DASHBOARD_QUERY_THRESHOLD', '0.5').to_f

# Rate limiting
Rails.application.config.analytics.rate_limit_per_minute = ENV.fetch('ANALYTICS_RATE_LIMIT', '100').to_i

# Batch processing
Rails.application.config.analytics.batch_size = ENV.fetch('ANALYTICS_BATCH_SIZE', '100').to_i
Rails.application.config.analytics.batch_interval_ms = ENV.fetch('ANALYTICS_BATCH_INTERVAL', '30000').to_i # 30 seconds

# Job configuration
Rails.application.config.analytics.snapshot_slow_threshold = ENV.fetch('ANALYTICS_SNAPSHOT_SLOW_THRESHOLD', '5.0').to_f # 5 seconds
Rails.application.config.analytics.snapshot_max_duration = ENV.fetch('ANALYTICS_SNAPSHOT_MAX_DURATION', '1800').to_i # 30 minutes
Rails.application.config.analytics.snapshot_error_threshold = ENV.fetch('ANALYTICS_SNAPSHOT_ERROR_THRESHOLD', '10').to_i

# Data retention (in days)
Rails.application.config.analytics.page_views_retention = ENV.fetch('ANALYTICS_PAGE_VIEWS_RETENTION', '90').to_i
Rails.application.config.analytics.click_events_retention = ENV.fetch('ANALYTICS_CLICK_EVENTS_RETENTION', '90').to_i
Rails.application.config.analytics.sessions_retention = ENV.fetch('ANALYTICS_SESSIONS_RETENTION', '90').to_i
Rails.application.config.analytics.snapshots_retention = ENV.fetch('ANALYTICS_SNAPSHOTS_RETENTION', '365').to_i

# Predictive analytics
Rails.application.config.analytics.forecast_min_data_points = ENV.fetch('ANALYTICS_FORECAST_MIN_DATA_POINTS', '7').to_i
Rails.application.config.analytics.forecast_default_days = ENV.fetch('ANALYTICS_FORECAST_DEFAULT_DAYS', '30').to_i

# Privacy
Rails.application.config.analytics.fingerprint_bits = ENV.fetch('ANALYTICS_FINGERPRINT_BITS', '128').to_i # 32 hex chars
Rails.application.config.analytics.ip_anonymization = ENV.fetch('ANALYTICS_IP_ANONYMIZATION', 'true') == 'true'

# External API timeouts (for SEO service)
Rails.application.config.analytics.http_timeout = ENV.fetch('ANALYTICS_HTTP_TIMEOUT', '10').to_i # seconds
Rails.application.config.analytics.http_open_timeout = ENV.fetch('ANALYTICS_HTTP_OPEN_TIMEOUT', '5').to_i # seconds
Rails.application.config.analytics.http_retry_attempts = ENV.fetch('ANALYTICS_HTTP_RETRY_ATTEMPTS', '3').to_i

# Query budget (prevent runaway queries)
Rails.application.config.analytics.max_query_records = ENV.fetch('ANALYTICS_MAX_QUERY_RECORDS', '100000').to_i

# Feature flags
Rails.application.config.analytics.enabled = ENV.fetch('ANALYTICS_ENABLED', 'true') == 'true'
Rails.application.config.analytics.realtime_enabled = ENV.fetch('ANALYTICS_REALTIME_ENABLED', 'true') == 'true'
Rails.application.config.analytics.predictive_enabled = ENV.fetch('ANALYTICS_PREDICTIVE_ENABLED', 'true') == 'true'

Rails.logger.info "[Analytics] Configuration loaded - enabled: #{Rails.application.config.analytics.enabled}"
