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

      # Schedule auto-cancel of unpaid product orders every 15 minutes
      SolidQueue::RecurringTask.find_or_create_by!(key: 'auto_cancel_unpaid_product_orders') do |task|
        task.schedule    = '*/15 * * * *' # every 15 minutes
        task.class_name  = 'AutoCancelUnpaidProductOrdersJob'
        task.arguments   = '[]'
        task.queue_name  = 'default'
        task.priority    = 0
        task.static      = true
        task.description = 'Auto cancel unpaid product orders after tier-specific deadlines'
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
