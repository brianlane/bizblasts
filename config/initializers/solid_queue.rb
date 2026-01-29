# frozen_string_literal: true

# Configure SolidQueue to work with the proper database
if defined?(SolidQueue)
  Rails.application.config.to_prepare do
    # Skip SolidQueue setup during asset compilation or when explicitly disabled
    next if ENV['RAILS_DISABLE_ASSET_COMPILATION'] == 'true'
    next if ENV['SKIP_SOLID_QUEUE_SETUP'] == 'true'
    next if Rails.env.test? && ENV['CI'].present? && ENV['RAILS_ENV'] != 'test'
    
    # Only proceed if we can actually connect to the database
    begin
      # Test database connection without triggering full schema load
      ActiveRecord::Base.connection.execute('SELECT 1')
      
      # Check if the solid_queue_recurring_tasks table exists
      unless ActiveRecord::Base.connection.table_exists?('solid_queue_recurring_tasks')
        Rails.logger.info "SolidQueue tables not found, skipping recurring task setup"
        next
      end
      
      Rails.application.config.active_job.queue_adapter = :solid_queue

      upsert_recurring_task = lambda do |key, attributes|
        task = SolidQueue::RecurringTask.find_or_initialize_by(key: key)
        task.assign_attributes(attributes)
        task.save! if task.changed?
      end

      # Stagger schedules to avoid memory spikes from concurrent jobs.
      # Each task uses a unique minute offset.

      # Schedule auto-cancel of unpaid product orders
      upsert_recurring_task.call(
        'auto_cancel_unpaid_product_orders',
        schedule: '7-59/15 * * * *', # every 15 minutes starting at :07
        class_name: 'AutoCancelUnpaidProductOrdersJob',
        arguments: '[]',
        queue_name: 'default',
        priority: 0,
        static: true,
        description: 'Auto cancel unpaid product orders after tier-specific deadlines'
      )
      
      # Schedule token refresh for calendar integrations
      upsert_recurring_task.call(
        'calendar_token_refresh',
        schedule: '12-59/5 * * * *', # every 5 minutes starting at :12
        class_name: 'Calendar::TokenRefreshJob',
        arguments: '[]',
        queue_name: 'low_priority',
        priority: 10,
        static: true,
        description: 'Proactively refresh expiring calendar OAuth tokens'
      )

      # Schedule rental overdue check
      upsert_recurring_task.call(
        'rental_overdue_check',
        schedule: '22 * * * *', # every hour at :22
        class_name: 'RentalOverdueCheckJob',
        arguments: '[]',
        queue_name: 'default',
        priority: 5,
        static: true,
        description: 'Check for overdue rentals and send notifications'
      )

      # Schedule rental reminders daily at 9 AM
      upsert_recurring_task.call(
        'rental_reminder',
        schedule: '35 9 * * *', # daily at 9:35 AM
        class_name: 'RentalReminderJob',
        arguments: '[]',
        queue_name: 'default',
        priority: 5,
        static: true,
        description: 'Send rental pickup and return reminders'
      )

      # Schedule invalidated session cleanup
      upsert_recurring_task.call(
        'invalidated_session_cleanup',
        schedule: '42 */6 * * *', # every 6 hours at :42
        class_name: 'InvalidatedSessionCleanupJob',
        arguments: '[]',
        queue_name: 'default',
        priority: 5,
        static: true,
        description: 'Purge expired invalidated sessions to keep the blacklist small'
      )

      # Schedule auth token cleanup
      upsert_recurring_task.call(
        'auth_token_cleanup',
        schedule: '48 2 * * *', # daily at 2:48 AM
        class_name: 'AuthTokenCleanupJob',
        arguments: '[]',
        queue_name: 'default',
        priority: 5,
        static: true,
        description: 'Remove expired cross-domain auth tokens'
      )

      # Schedule OAuth flash message cleanup
      upsert_recurring_task.call(
        'oauth_flash_message_cleanup',
        schedule: '13-59/15 * * * *', # every 15 minutes starting at :13
        class_name: 'OauthFlashMessageCleanupJob',
        arguments: '[]',
        queue_name: 'default',
        priority: 10,
        static: true,
        description: 'Remove used/expired OAuth flash tokens'
      )

      # Schedule email marketing token refresh
      upsert_recurring_task.call(
        'email_marketing_token_refresh',
        schedule: '18 * * * *', # every hour at :18
        class_name: 'EmailMarketing::TokenRefreshJob',
        arguments: '[]',
        queue_name: 'email_marketing',
        priority: 10,
        static: true,
        description: 'Refresh expiring email marketing OAuth tokens'
      )

      # Schedule analytics session aggregation
      upsert_recurring_task.call(
        'analytics_session_aggregation',
        schedule: '25 * * * *', # every hour at :25
        class_name: 'Analytics::SessionAggregationJob',
        arguments: '[]',
        queue_name: 'analytics',
        priority: 10,
        static: true,
        description: 'Close inactive analytics sessions'
      )

      # Schedule analytics daily snapshot
      upsert_recurring_task.call(
        'analytics_daily_snapshot',
        schedule: '31 2 * * *', # daily at 2:31 AM
        class_name: 'Analytics::DailySnapshotJob',
        arguments: '[]',
        queue_name: 'analytics',
        priority: 10,
        static: true,
        description: 'Generate daily analytics summary'
      )

      # Schedule analytics SEO analysis
      upsert_recurring_task.call(
        'analytics_seo_analysis',
        schedule: '37 3 * * *', # daily at 3:37 AM
        class_name: 'Analytics::SeoAnalysisJob',
        arguments: '[]',
        queue_name: 'analytics',
        priority: 10,
        static: true,
        description: 'Refresh SEO scores and suggestions'
      )

      # Schedule analytics cleanup
      upsert_recurring_task.call(
        'analytics_cleanup',
        schedule: '49 4 * * 0', # weekly on Sunday at 4:49 AM UTC
        class_name: 'Analytics::CleanupJob',
        arguments: '[]',
        queue_name: 'analytics',
        priority: 20,
        static: true,
        description: 'Remove old raw analytics data'
      )

      # Schedule SolidQueue job pruning daily at 3 AM UTC
      upsert_recurring_task.call(
        'solid_queue_pruner',
        schedule: '44 3 * * *', # daily at 3:44 AM
        class_name: 'SolidQueuePruneJob',
        arguments: '[{"retention_days":14}]',
        queue_name: 'default',
        priority: 20,
        static: true,
        description: 'Remove completed SolidQueue jobs older than the retention window'
      )

      # Schedule calendar availability imports
      # This replaces the self-scheduling that was causing job pile-up
      upsert_recurring_task.call(
        'calendar_availability_import',
        schedule: '53 */2 * * *', # every 2 hours at :53
        class_name: 'Calendar::ScheduleImportsJob',
        arguments: '[]',
        queue_name: 'default',
        priority: 10,
        static: true,
        description: 'Schedule calendar availability imports for all staff with connected calendars'
      )

      Rails.logger.info "SolidQueue recurring tasks configured successfully"
      
    rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::NoDatabaseError, PG::ConnectionBad => e
      Rails.logger.info "Database not available for SolidQueue setup: #{e.message}"
      # Don't fail the application startup, just skip SolidQueue setup
    rescue ActiveRecord::StatementInvalid => e
      Rails.logger.info "Database schema not ready for SolidQueue: #{e.message}"
      # Table might not exist yet, skip setup
    rescue => e
      Rails.logger.warn "Unexpected error during SolidQueue setup: #{e.message}"
      # Log but don't fail
    end
  end
end
