class StripeWebhookJob < ApplicationJob
  queue_as :default

  def perform(payload, sig_header)
    stripe_credentials = Rails.application.credentials.stripe || {}
    endpoint_secret = stripe_credentials[:webhook_secret] || ENV['STRIPE_WEBHOOK_SECRET']

    begin
      event = Stripe::Webhook.construct_event(payload, sig_header, endpoint_secret)
    rescue JSON::ParserError => e
      Rails.logger.error "Stripe Webhook JSON parse error: #{e.message}"
      return
    rescue Stripe::SignatureVerificationError => e
      Rails.logger.error "Stripe Webhook signature error: #{e.message}"
      return
    end

    # Delegate to central service
    StripeService.process_webhook(event.to_json)
  rescue => e
    Rails.logger.error "StripeWebhookJob failed: #{e.message}" 
    raise e
  end
end 