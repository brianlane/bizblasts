# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    # Simple sequence to avoid validation complexity
    sequence(:email) { |n| "user#{n}@example.com" }
    first_name { "Test" }
    sequence(:last_name) { |n| "User#{n}" }
    password { "password123" }
    password_confirmation { "password123" }
    role { :client }
    active { true }
    # Confirm users by default for tests
    confirmed_at { Time.current }
    # Default notification preferences will be set by after_create callback
    notification_preferences { nil }
    
    trait :unconfirmed do
      confirmed_at { nil }
    end
    
    trait :with_staff_member do
      association :staff_member, strategy: :build
    end
    
    trait :manager do
      role { :manager }
      association :business
    end
    
    trait :staff do
      role { :staff }
      association :business
    end
    
    trait :client do
      role { :client }
      business { nil }
    end
  end
end 