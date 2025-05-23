class StripeWebhooksController < ApplicationController
  # Skip CSRF and auth for webhooks
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!

  # POST /webhooks/stripe
  def create
    payload = request.body.read
    sig_header = request.env['HTTP_STRIPE_SIGNATURE']
    StripeWebhookJob.perform_later(payload, sig_header)
    head :ok
  end
end 