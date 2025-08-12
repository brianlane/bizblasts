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
    # ActiveJob serialization can use symbol or string keys; support both.
    if kwargs.empty? && args.length == 4 && args[3].is_a?(Hash)
      mailer_class, method_name, delivery_method, args_hash = args
      actual_args   = args_hash.key?(:args)   ? args_hash[:args]   : args_hash['args']
      actual_kwargs = args_hash.key?(:kwargs) ? args_hash[:kwargs] : args_hash['kwargs']
      actual_params = args_hash.key?(:params) ? args_hash[:params] : args_hash['params']

      if !actual_args.nil? || !actual_kwargs.nil? || !actual_params.nil?
        # Ensure kwargs keys are symbols so Ruby keyword splat works reliably on Ruby 3+
        actual_kwargs = actual_kwargs.transform_keys(&:to_sym) if actual_kwargs.is_a?(Hash)
        # Always provide args: (required by Rails 8 signature), default to []
        if actual_kwargs && actual_params
          super(mailer_class, method_name, delivery_method, args: (actual_args || []), kwargs: actual_kwargs, params: actual_params)
        elsif actual_kwargs
          super(mailer_class, method_name, delivery_method, args: (actual_args || []), kwargs: actual_kwargs)
        elsif actual_params
          super(mailer_class, method_name, delivery_method, args: (actual_args || []), params: actual_params)
        else
          super(mailer_class, method_name, delivery_method, args: actual_args)
        end
      else
        super(*args)
      end
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