# frozen_string_literal: true

FactoryBot.define do
  factory :tenant_customer do
    first_name { Faker::Name.first_name }
    last_name { Faker::Name.last_name }
    email { Faker::Internet.email }
    phone { Faker::PhoneNumber.phone_number }
    address { Faker::Address.full_address }
    notes { Faker::Lorem.paragraph }
    active { true }
    association :business
    # Default email preferences will be set by after_create callback
    email_marketing_opt_out { nil }
    unsubscribed_at { nil }
    
    trait :inactive do
      active { false }
    end
    
    trait :with_bookings do
      transient do
        bookings_count { 2 }
      end
      
      after(:create) do |customer, evaluator|
        create_list(:booking, evaluator.bookings_count, tenant_customer: customer, business: customer.business)
      end
    end
  end
end 