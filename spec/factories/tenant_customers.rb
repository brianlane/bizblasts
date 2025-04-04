# frozen_string_literal: true

FactoryBot.define do
  factory :tenant_customer do
    # Simple sequence to avoid validation complexity
    sequence(:name) { |n| "Customer #{n}" }
    sequence(:email) { |n| "customer#{n}@example.com" }
    
    # Static data to avoid computations
    phone { "555-123-4567" }
    notes { "Test customer" }
    
    # Skip callbacks for test performance
    to_create { |instance| 
      instance.save(validate: false) 
    }
    
    # Minimize database operations by using build instead of create for associations
    association :business, strategy: :build
    
    trait :with_bookings do
      after(:create) do |customer, evaluator|
        create_list(:booking, 2, tenant_customer: customer, business: customer.business)
      end
    end
  end
end 