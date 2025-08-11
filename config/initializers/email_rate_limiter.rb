# frozen_string_literal: true
# Global rate-limiter for ALL outbound email jobs.
# Most ESPs (Postmark, Mailgun, etc.) impose per-second request limits.
# We prepend a small throttling wrapper to ActionMailer::MailDeliveryJob so that
# we never exceed the allowed throughput – regardless of which job queued the
# email (BlogNotificationJob, invoice mailers, devise emails, etc.).
#
# Default: 2 requests/second (Postmark free tier).  Override with the
# EMAIL_RATE_LIMIT_PER_SECOND env variable in production.

return unless defined?(ActionMailer::MailDeliveryJob)

module EmailRateLimiter
  RATE_PER_SECOND = (ENV.fetch("EMAIL_RATE_LIMIT_PER_SECOND", 2).to_i).positive? ? ENV.fetch("EMAIL_RATE_LIMIT_PER_SECOND", 2).to_i : 2
  MIN_INTERVAL   = 1.0 / RATE_PER_SECOND

  # Support Rails 7/8 MailDeliveryJob signature (keywords) and older forms
  def perform(*args, **kwargs)
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_second)

    # Rails 8.0.2 ActionMailer::MailDeliveryJob expects:
    # perform(mailer_class, method_name, delivery_method, args:)
    # But jobs may be enqueued with 4 positional arguments, where the 4th should be the args: keyword
    if kwargs.empty? && args.length == 4 && args[3].is_a?(Hash) && args[3].key?('args')
      # Convert 4th positional argument to keyword argument
      mailer_class, method_name, delivery_method, args_hash = args
      super(mailer_class, method_name, delivery_method, args: args_hash['args'])
    elsif kwargs.empty?
      super(*args)
    else
      super(*args, **kwargs)
    end
  ensure
    elapsed   = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_second) - started_at
    # Sleep long enough so that this worker thread respects the global rate.
    # With N worker threads the total theoretical max throughput becomes
    # N / (1 / RATE_PER_SECOND).  To remain safe, run the `mailers` queue with
    # 1-2 threads in production.
    remaining = MIN_INTERVAL - elapsed
    sleep(remaining) if remaining.positive?
  end
end

# Prepend so our wrapper runs *around* the original perform implementation.
ActionMailer::MailDeliveryJob.prepend(EmailRateLimiter)

Rails.logger.info "[EmailRateLimiter] Loaded – throttling outgoing mail to #{EmailRateLimiter::RATE_PER_SECOND} req/s per worker thread"