# frozen_string_literal: true

FactoryBot.define do
  factory :tenant_customer do
    # Simple sequence to avoid validation complexity
    sequence(:name) { |n| "Customer #{n}" }
    sequence(:email) { |n| "customer#{n}@example.com" }
    
    # Static data to avoid computations
    phone { "555-123-4567" }
    notes { "Test customer" }
    
    # Association should be set correctly
    association :business 
    
    trait :with_bookings do
      after(:create) do |customer, evaluator|
        create_list(:booking, 2, tenant_customer: customer, business: customer.business)
      end
    end
  end
end 