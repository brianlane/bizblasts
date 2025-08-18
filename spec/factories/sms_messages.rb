FactoryBot.define do
  factory :sms_message do
    association :tenant_customer
    association :marketing_campaign
    
    phone_number { tenant_customer&.phone || "+15551234567" } 
    content { "Your booking reminder." }
    status { :sent } 
    sent_at { 1.minute.ago }
    external_id { "plivo-uuid-#{SecureRandom.hex(8)}" }  # Plivo-style UUID

    trait :delivered do
      status { :delivered }
      delivered_at { Time.current }
      external_id { "plivo-uuid-delivered-#{SecureRandom.hex(8)}" }
    end

    trait :failed do
      status { :failed }
      error_message { "Plivo API error: Invalid destination number" }
      external_id { "plivo-uuid-failed-#{SecureRandom.hex(8)}" }
    end
    
    trait :pending do 
      status { :pending }
      sent_at { nil }
      external_id { nil }
    end

    # Trait for testing with specific external_id
    trait :with_external_id do
      transient do
        uuid { "plivo-uuid-test-#{SecureRandom.hex(8)}" }
      end
      external_id { uuid }
    end

    # Trait for booking-related SMS
    trait :booking_confirmation do
      association :booking
      marketing_campaign { nil }
      content { "Booking confirmed: #{booking.service&.name} on #{booking.local_start_time&.strftime('%b %d at %I:%M %p')}." }
    end

    # Trait for marketing campaign SMS
    trait :marketing do
      association :marketing_campaign
      booking { nil }
      content { "Check out our latest offers!" }
    end
  end
end 