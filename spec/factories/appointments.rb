FactoryBot.define do
  factory :appointment do
    # Associations - assumes factories for business, service, staff_member, and tenant_customer exist
    association :business
    association :service
    association :staff_member
    association :tenant_customer, factory: :tenant_customer

    # Attributes
    start_time { Time.current + 1.day }
    end_time { start_time + 1.hour }
    status { 'scheduled' }
    price { 100.00 }
    notes { Faker::Lorem.paragraph(sentence_count: 2) }
    metadata { {} }
    paid { false }
    # stripe_payment_intent_id { nil } # Usually set after creation
    # stripe_customer_id { nil } # Usually set after creation
    # cancelled_at { nil }
    # cancellation_reason { nil }
  end
end 