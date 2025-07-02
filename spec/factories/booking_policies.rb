FactoryBot.define do
  factory :booking_policy do
    association :business
    cancellation_window_mins { 0 }
    buffer_time_mins { 0 }
    max_daily_bookings { 0 }
    max_advance_days { 30 } # Allow bookings up to 30 days in advance by default
    min_duration_mins { nil }
    max_duration_mins { nil }
    intake_fields { {} }
    auto_confirm_bookings { false }

    # Allow traits or customization if needed
    
    trait :with_duration_constraints do
      min_duration_mins { 30 }
      max_duration_mins { 240 } # 4 hours
    end
  end
end 