class StripeWebhooksController < ApplicationController
  # Skip CSRF and auth for webhooks
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!

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
      
      StripeWebhookJob.perform_later(payload, sig_header)
      head :ok
    rescue => e
      Rails.logger.error "Stripe webhook controller error: #{e.message}"
      head :ok
    end
  end
end 