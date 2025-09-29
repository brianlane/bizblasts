# frozen_string_literal: true

FactoryBot.define do
  factory :invalidated_session do
    user { association :user }
    session_token { SecureRandom.urlsafe_base64(32) }
    invalidated_at { Time.current }
    expires_at { 24.hours.from_now }

    trait :expired do
      expires_at { 1.hour.ago }
    end

    trait :active do
      expires_at { 1.hour.from_now }
    end

    trait :long_lived do
      expires_at { 7.days.from_now }
    end
  end
end
