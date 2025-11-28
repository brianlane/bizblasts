# frozen_string_literal: true

FactoryBot.define do
  factory :rental_booking do
    association :business
    association :product, factory: :product, product_type: :rental
    association :tenant_customer
    
    start_time { 1.day.from_now }
    end_time { 3.days.from_now }
    quantity { 1 }
    rate_type { 'daily' }
    rate_amount { 50.00 }
    rate_quantity { 2 }
    subtotal { 100.00 }
    security_deposit_amount { 50.00 }
    tax_amount { 0 }
    total_amount { 100.00 }
    status { 'pending_deposit' }
    deposit_status { 'pending' }
    
    after(:build) do |booking|
      booking.booking_number ||= "RNT-#{SecureRandom.hex(6).upcase}"
      booking.guest_access_token ||= SecureRandom.urlsafe_base64(32)
    end
    
    trait :with_deposit_paid do
      status { 'deposit_paid' }
      deposit_status { 'collected' }
      deposit_paid_at { Time.current }
    end
    
    trait :checked_out do
      status { 'checked_out' }
      deposit_status { 'collected' }
      deposit_paid_at { 1.day.ago }
      actual_pickup_time { Time.current }
    end
    
    trait :overdue do
      status { 'overdue' }
      deposit_status { 'collected' }
      deposit_paid_at { 5.days.ago }
      actual_pickup_time { 4.days.ago }
      start_time { 4.days.ago }
      end_time { 1.day.ago }
    end
    
    trait :returned do
      status { 'returned' }
      deposit_status { 'full_refund' }
      deposit_paid_at { 5.days.ago }
      actual_pickup_time { 4.days.ago }
      actual_return_time { Time.current }
      deposit_refund_amount { 50.00 }
    end
    
    trait :completed do
      status { 'completed' }
      deposit_status { 'full_refund' }
      deposit_paid_at { 5.days.ago }
      actual_pickup_time { 4.days.ago }
      actual_return_time { 1.day.ago }
      deposit_refund_amount { 50.00 }
      deposit_refunded_at { Time.current }
    end
    
    trait :cancelled do
      status { 'cancelled' }
      deposit_status { 'pending' }
    end
  end
end

