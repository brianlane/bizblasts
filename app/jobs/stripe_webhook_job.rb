class StripeWebhookJob < ApplicationJob
  queue_as :default

  def perform(payload, sig_header, tenant_id = nil)
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

    # Set tenant context if provided
    if tenant_id
      tenant = Business.find_by(id: tenant_id)
      if tenant
        ActsAsTenant.with_tenant(tenant) do
          Rails.logger.info "[WEBHOOK_JOB] Processing webhook with tenant context: #{tenant.name} (ID: #{tenant.id})"
          StripeService.process_webhook(event.to_json, tenant)
        end
      else
        Rails.logger.error "[WEBHOOK_JOB] Could not find tenant with ID: #{tenant_id}"
        StripeService.process_webhook(event.to_json, nil)
      end
    else
      Rails.logger.info "[WEBHOOK_JOB] Processing webhook without tenant context"
      StripeService.process_webhook(event.to_json, nil)
    end
  rescue => e
    Rails.logger.error "StripeWebhookJob failed: #{e.message}" 
    raise e
  end
end 