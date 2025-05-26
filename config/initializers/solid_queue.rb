# frozen_string_literal: true

# Configure SolidQueue to work with the proper database
if defined?(SolidQueue)
  Rails.application.config.to_prepare do
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
  end
end
