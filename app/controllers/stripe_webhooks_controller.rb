class StripeWebhooksController < ApplicationController
  # SECURITY: CSRF skip is LEGITIMATE for external webhooks
  # - This is called by Stripe servers, not user browsers (no session context)
  # - Security is provided by Stripe signature verification (see line 12-13, 50)
  # - Webhook endpoint secret validates authenticity of requests
  # Related security: CWE-352 (CSRF) mitigation via alternative authentication
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!
  # Skip tenant setting since we'll handle it manually from webhook data
  skip_before_action :set_tenant

  # POST /webhooks/stripe
  def create
    begin
      payload = request.body.read
      sig_header = request.env['HTTP_STRIPE_SIGNATURE']
      
      # Validate that we have a payload
      if payload.blank?
        Rails.logger.warn "Stripe webhook received empty payload"
        head :ok
        return
      end
      
      # Extract tenant context from webhook before processing
      tenant_context = extract_tenant_context_from_webhook(payload, sig_header)
      
      # Set tenant context if found
      if tenant_context
        ActsAsTenant.with_tenant(tenant_context) do
          Rails.logger.info "[WEBHOOK] Processing webhook with tenant context: #{tenant_context.name} (ID: #{tenant_context.id})"
          StripeWebhookJob.perform_later(payload, sig_header, tenant_context.id)
        end
      else
        Rails.logger.info "[WEBHOOK] Processing webhook without tenant context"
        StripeWebhookJob.perform_later(payload, sig_header, nil)
      end
      
      head :ok
    rescue => e
      Rails.logger.error "Stripe webhook controller error: #{e.message}"
      head :ok
    end
  end

  private

  def extract_tenant_context_from_webhook(payload, sig_header)
    # Parse the webhook event to extract tenant information
    stripe_credentials = Rails.application.credentials.stripe || {}
    endpoint_secret = stripe_credentials[:webhook_secret] || ENV['STRIPE_WEBHOOK_SECRET']
    
    begin
      event = Stripe::Webhook.construct_event(payload, sig_header, endpoint_secret)
      
      # Extract business_id from various webhook event types
      business_id = find_business_id_from_event(event)
      
      if business_id
        business = Business.find_by(id: business_id)
        if business
          Rails.logger.info "[WEBHOOK] Found tenant context from webhook: #{business.name} (ID: #{business.id})"
          return business
        end
      end
      
      # Fallback: try to find business from connected account
      if event.account
        business = Business.find_by(stripe_account_id: event.account)
        if business
          Rails.logger.info "[WEBHOOK] Found tenant context from connected account: #{business.name} (ID: #{business.id})"
          return business
        end
      end
      
      Rails.logger.warn "[WEBHOOK] Could not extract tenant context from webhook event: #{event.type}"
      nil
    rescue JSON::ParserError, Stripe::SignatureVerificationError => e
      Rails.logger.error "[WEBHOOK] Error parsing webhook for tenant context: #{e.message}"
      nil
    end
  end

  def find_business_id_from_event(event)
    # Check metadata for business_id in various event types
    obj = event.data.object
    case event.type
    when 'payment_intent.succeeded', 'payment_intent.payment_failed'
      obj.metadata['business_id']
    when 'checkout.session.completed'
      obj.metadata['business_id']
    when 'invoice.payment_succeeded', 'invoice.payment_failed'
      # For invoice events, we need to find the business through the subscription or customer
      if obj.subscription
        # Find customer subscription to get business
        customer_subscription = CustomerSubscription.unscoped.find_by(stripe_subscription_id: obj.subscription)
        return customer_subscription&.business_id
      end
      # Check invoice metadata
      obj.metadata['business_id']
    when 'customer.subscription.created', 'customer.subscription.updated', 'customer.subscription.deleted'
      # Find from subscription metadata
      obj.metadata['business_id']
    else
      # Check if the event object has metadata with business_id
      obj.metadata['business_id'] if obj.respond_to?(:metadata)
    end
  end
end 