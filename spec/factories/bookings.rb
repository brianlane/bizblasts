# frozen_string_literal: true

FactoryBot.define do
  factory :booking do
    association :business
    association :service 
    association :staff_member
    association :tenant_customer
    
    start_time { Time.current.beginning_of_hour + 1.day + 9.hours } # Default to 9 AM tomorrow
    
    # Calculate end_time based on start_time and service duration
    # Use transient attribute to allow passing duration if service is not set
    transient do
      duration_minutes { service&.duration || 60 } # Default to 60 mins if no service
    end
    end_time { start_time + duration_minutes.minutes if start_time }
    
    status { :confirmed }
    notes { "Test booking details." }
    amount { service&.price } # Set amount from service price
    # promotion, original_amount, discount_amount usually set by services
  end
end 