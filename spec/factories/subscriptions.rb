# frozen_string_literal: true

FactoryBot.define do
  factory :subscription do
    association :business
    plan_name { ['free', 'standard', 'premium'].sample } # Or a more specific plan
    sequence(:stripe_subscription_id) { |n| "sub_#{SecureRandom.hex(4)}#{n}" }
    status { 'active' } # Common statuses: active, past_due, canceled, trialing
    current_period_end { Time.current + 1.month }

    trait :trialing do
      status { 'trialing' }
      current_period_end { Time.current + 14.days }
    end

    trait :canceled do
      status { 'canceled' }
      current_period_end { Time.current - 1.day } # Or when it was canceled
    end

    trait :past_due do
      status { 'past_due' }
    end
  end
end 