# frozen_string_literal: true

# Email Marketing Integration Configuration
#
# This file contains configuration settings for email marketing integrations
# (Mailchimp, Constant Contact). Settings can be overridden via environment
# variables for different environments.

Rails.application.config.email_marketing = ActiveSupport::OrderedOptions.new

# ==============================================================================
# Mailchimp Webhook IP Allowlist
# ==============================================================================
#
# Mailchimp doesn't send a signature header by default, so we verify webhook
# authenticity by checking the source IP address against Mailchimp's published
# webhook IP ranges.
#
# These IPs are from Mailchimp's official documentation:
# https://mailchimp.com/about/ips/
#
# IMPORTANT: Review and update this list periodically. Mailchimp may add or
# remove IPs from their webhook infrastructure. Check the URL above for the
# latest list.
#
# Last updated: December 2024
#
# For production use, we recommend also configuring a webhook secret
# (MAILCHIMP_WEBHOOK_SECRET) as an additional layer of security.
#
Rails.application.config.email_marketing.mailchimp_webhook_ips = ENV.fetch(
  'MAILCHIMP_WEBHOOK_IPS',
  '52.23.45.43,52.204.253.38,52.204.255.205,54.85.123.78,54.87.214.91,' \
  '54.208.115.215,54.209.221.135,54.221.253.203,54.224.62.94,54.224.148.131,' \
  '54.226.12.205,54.227.4.208,54.227.107.57,54.231.189.82,54.231.242.40,' \
  '54.237.188.163,54.242.175.77'
).split(',').map(&:strip).freeze

# ==============================================================================
# Batch Sync Thresholds
# ==============================================================================
#
# When syncing contacts to email marketing platforms, we use batch APIs for
# efficiency when the number of contacts exceeds these thresholds.
#
# These values can be customized per provider to account for different API
# rate limits and batch size limits.
#
Rails.application.config.email_marketing.batch_thresholds = {
  # Mailchimp supports up to 500 operations per batch, but smaller batches
  # are more reliable and easier to debug
  mailchimp: ENV.fetch('EMAIL_MARKETING_MAILCHIMP_BATCH_THRESHOLD', 50).to_i,

  # Constant Contact's bulk import API handles larger batches well
  constant_contact: ENV.fetch('EMAIL_MARKETING_CONSTANT_CONTACT_BATCH_THRESHOLD', 50).to_i,

  # Default threshold for any new providers
  default: ENV.fetch('EMAIL_MARKETING_DEFAULT_BATCH_THRESHOLD', 50).to_i
}.freeze

# ==============================================================================
# Token Refresh Settings
# ==============================================================================
#
# OAuth tokens need to be refreshed before they expire. These settings control
# when the token refresh job considers a token as "needing refresh".
#
Rails.application.config.email_marketing.token_refresh_buffer_minutes =
  ENV.fetch('EMAIL_MARKETING_TOKEN_REFRESH_BUFFER_MINUTES', 5).to_i
