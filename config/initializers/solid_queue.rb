# frozen_string_literal: true

# Configure SolidQueue to work with the proper database
if defined?(SolidQueue)
  Rails.application.config.to_prepare do
    Rails.application.config.active_job.queue_adapter = :solid_queue
  end
end
