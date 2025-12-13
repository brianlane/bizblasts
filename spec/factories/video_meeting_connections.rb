# frozen_string_literal: true

FactoryBot.define do
  factory :video_meeting_connection do
    association :business
    association :staff_member
    provider { :zoom }
    access_token { SecureRandom.hex(32) }
    refresh_token { SecureRandom.hex(32) }
    token_expires_at { 1.hour.from_now }
    active { true }
    uid { "user_#{SecureRandom.hex(8)}" }
    connected_at { Time.current }

    trait :zoom do
      provider { :zoom }
    end

    trait :google_meet do
      provider { :google_meet }
    end

    trait :expired do
      token_expires_at { 1.hour.ago }
    end

    trait :expiring_soon do
      token_expires_at { 3.minutes.from_now }
    end

    trait :inactive do
      active { false }
    end

    trait :without_refresh_token do
      refresh_token { nil }
    end
  end
end
