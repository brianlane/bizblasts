# frozen_string_literal: true

FactoryBot.define do
  factory :stock_reservation do
    # Required associations
    association :product_variant
    association :order
    
    # Reservation details
    quantity { 1 }
    expires_at { 1.hour.from_now }
    
    # Timestamps
    created_at { 1.minute.ago }
    updated_at { 1.minute.ago }
    
    # Traits for different quantities
    trait :multiple_quantity do
      quantity { 5 }
    end
    
    trait :large_quantity do
      quantity { 10 }
    end
    
    # Traits for different expiry times
    trait :expires_soon do
      expires_at { 5.minutes.from_now }
    end
    
    trait :expired do
      expires_at { 1.hour.ago }
    end
    
    trait :long_expiry do
      expires_at { 24.hours.from_now }
    end
  end
end 