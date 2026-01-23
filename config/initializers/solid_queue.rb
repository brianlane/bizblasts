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

      low_usage_mode = ENV.fetch('LOW_USAGE_MODE', 'false') == 'true'

      schedule_for = lambda do |normal:, low_usage:|
        low_usage_mode ? low_usage : normal
      end

      # Schedule auto-cancel of unpaid product orders
      SolidQueue::RecurringTask.find_or_create_by!(key: 'auto_cancel_unpaid_product_orders') do |task|
        task.schedule    = schedule_for.call(
          normal: '*/15 * * * *', # every 15 minutes
          low_usage: '0 */2 * * *' # every 2 hours
        )
        task.class_name  = 'AutoCancelUnpaidProductOrdersJob'
        task.arguments   = '[]'
        task.queue_name  = 'default'
        task.priority    = 0
        task.static      = true
        task.description = 'Auto cancel unpaid product orders after tier-specific deadlines'
      end
      
      # Schedule token refresh for calendar integrations
      SolidQueue::RecurringTask.find_or_create_by!(key: 'calendar_token_refresh') do |task|
        task.schedule    = schedule_for.call(
          normal: '*/5 * * * *', # every 5 minutes
          low_usage: '0 * * * *' # every hour
        )
        task.class_name  = 'Calendar::TokenRefreshJob'
        task.arguments   = '[]'
        task.queue_name  = 'low_priority'
        task.priority    = 10
        task.static      = true
        task.description = 'Proactively refresh expiring calendar OAuth tokens'
      end

      # Schedule rental overdue check
      SolidQueue::RecurringTask.find_or_create_by!(key: 'rental_overdue_check') do |task|
        task.schedule    = schedule_for.call(
          normal: '0 * * * *', # every hour at minute 0
          low_usage: '0 */6 * * *' # every 6 hours
        )
        task.class_name  = 'RentalOverdueCheckJob'
        task.arguments   = '[]'
        task.queue_name  = 'default'
        task.priority    = 5
        task.static      = true
        task.description = 'Check for overdue rentals and send notifications'
      end

      # Schedule rental reminders daily at 9 AM
      SolidQueue::RecurringTask.find_or_create_by!(key: 'rental_reminder') do |task|
        task.schedule    = '0 9 * * *' # daily at 9:00 AM
        task.class_name  = 'RentalReminderJob'
        task.arguments   = '[]'
        task.queue_name  = 'default'
        task.priority    = 5
        task.static      = true
        task.description = 'Send rental pickup and return reminders'
      end

      # Schedule invalidated session cleanup
      SolidQueue::RecurringTask.find_or_create_by!(key: 'invalidated_session_cleanup') do |task|
        task.schedule    = schedule_for.call(
          normal: '0 */6 * * *',
          low_usage: '0 3 * * *' # daily at 3 AM
        )
        task.class_name  = 'InvalidatedSessionCleanupJob'
        task.arguments   = '[]'
        task.queue_name  = 'default'
        task.priority    = 5
        task.static      = true
        task.description = 'Purge expired invalidated sessions to keep the blacklist small'
      end

      # Schedule SolidQueue job pruning daily at 3 AM UTC
      SolidQueue::RecurringTask.find_or_create_by!(key: 'solid_queue_pruner') do |task|
        task.schedule    = schedule_for.call(
          normal: '0 3 * * *',
          low_usage: '0 4 * * 0' # weekly on Sunday at 4 AM UTC
        )
        task.class_name  = 'SolidQueuePruneJob'
        task.arguments   = '[{"retention_days":14}]'
        task.queue_name  = 'default'
        task.priority    = 20
        task.static      = true
        task.description = 'Remove completed SolidQueue jobs older than the retention window'
      end

      # Schedule calendar availability imports
      # This replaces the self-scheduling that was causing job pile-up
      SolidQueue::RecurringTask.find_or_create_by!(key: 'calendar_availability_import') do |task|
        task.schedule    = schedule_for.call(
          normal: '0 */2 * * *', # every 2 hours at minute 0
          low_usage: '0 2 * * *' # daily at 2 AM
        )
        task.class_name  = 'Calendar::ScheduleImportsJob'
        task.arguments   = '[]'
        task.queue_name  = 'default'
        task.priority    = 10
        task.static      = true
        task.description = 'Schedule calendar availability imports for all staff with connected calendars'
      end

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
