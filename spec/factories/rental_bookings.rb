# frozen_string_literal: true

FactoryBot.define do
  factory :rental_booking do
    association :business
    association :product, factory: [:product, :rental]
    association :tenant_customer

    start_time { 1.day.from_now }
    end_time { 3.days.from_now }
    quantity { 1 }
    rate_type { 'daily' }

    # Calculate pricing dynamically from the product
    after(:build) do |booking|
      # Generate booking identifiers
      booking.booking_number ||= "RNT-#{SecureRandom.hex(6).upcase}"
      booking.guest_access_token ||= SecureRandom.urlsafe_base64(32)

      # Pull security deposit from product
      booking.security_deposit_amount ||= booking.product.security_deposit

      # Calculate rental pricing based on product rates
      pricing = booking.product.calculate_rental_price(
        booking.start_time,
        booking.end_time,
        rate_type: booking.rate_type
      )

      if pricing
        booking.rate_amount ||= pricing[:rate]
        booking.rate_quantity ||= pricing[:quantity]
        booking.subtotal ||= pricing[:total]
        booking.total_amount ||= pricing[:total]
        booking.tax_amount ||= 0
      else
        # Fallback if pricing calculation fails (shouldn't happen with valid rental product)
        booking.rate_amount ||= booking.product.daily_rate
        booking.rate_quantity ||= 2
        booking.subtotal ||= booking.product.daily_rate * 2
        booking.total_amount ||= booking.product.daily_rate * 2
        booking.tax_amount ||= 0
      end
    end

    # Default status values
    status { 'pending_deposit' }
    deposit_status { 'pending' }
    
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

      after(:create) do |booking|
        # Full refund = return the entire security deposit
        # Use after(:create) because security_deposit_amount is set in before_validation callback
        booking.update_column(:deposit_refund_amount, booking.security_deposit_amount)
      end
    end

    trait :completed do
      status { 'completed' }
      deposit_status { 'full_refund' }
      deposit_paid_at { 5.days.ago }
      actual_pickup_time { 4.days.ago }
      actual_return_time { 1.day.ago }
      deposit_refunded_at { Time.current }

      after(:create) do |booking|
        # Full refund = return the entire security deposit
        # Use after(:create) because security_deposit_amount is set in before_validation callback
        booking.update_column(:deposit_refund_amount, booking.security_deposit_amount)
      end
    end
    
    trait :cancelled do
      status { 'cancelled' }
      deposit_status { 'pending' }
    end
  end
end

