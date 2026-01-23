# frozen_string_literal: true

# Lazy-load heavy integration gems to reduce baseline memory usage.
# These modules/constants will autoload the gem only when referenced.

Object.autoload(:Stripe, 'stripe') unless defined?(Stripe)
Object.autoload(:Twilio, 'twilio-ruby') unless defined?(Twilio)
Object.autoload(:Aws, 'aws-sdk-s3') unless defined?(Aws)
Object.autoload(:OAuth2, 'oauth2') unless defined?(OAuth2)
Object.autoload(:HTTParty, 'httparty') unless defined?(HTTParty)
Object.autoload(:Icalendar, 'icalendar') unless defined?(Icalendar)
Object.autoload(:Prawn, 'prawn') unless defined?(Prawn)
Object.autoload(:RQRCode, 'rqrcode') unless defined?(RQRCode)
Object.autoload(:ChunkyPNG, 'chunky_png') unless defined?(ChunkyPNG)
Object.autoload(:MicrosoftGraph, 'microsoft_graph') unless defined?(MicrosoftGraph)

unless defined?(Google)
  module Google
  end
end

Google.autoload(:Apis, 'google/apis/calendar_v3') unless Google.const_defined?(:Apis)
Google.autoload(:Auth, 'googleauth') unless Google.const_defined?(:Auth)
