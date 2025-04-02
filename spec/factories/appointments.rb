FactoryBot.define do
  factory :appointment do
    # Associations - assumes factories for company, service, service_provider, and customer exist
    association :company
    association :service
    association :service_provider
    association :customer

    # Attributes from migration
    client_name { customer.name } # Or use Faker::Name.name if customer might not be available
    client_email { customer.email } # Or use Faker::Internet.email
    client_phone { customer.phone } # Or use Faker::PhoneNumber.phone_number
    start_time { Time.current + 1.day } 
    end_time { start_time + service.duration_minutes.minutes } # Calculate based on service duration
    status { 'scheduled' } # Default status
    price { service.price } # Get price from associated service
    notes { Faker::Lorem.sentence }
    metadata { {} }
    paid { false }
    # stripe_payment_intent_id { nil } # Usually set after creation
    # stripe_customer_id { nil } # Usually set after creation
    # cancelled_at { nil }
    # cancellation_reason { nil }
  end
end 