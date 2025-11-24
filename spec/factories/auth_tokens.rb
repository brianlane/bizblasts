# frozen_string_literal: true

FactoryBot.define do
  factory :auth_token do
    association :user
    target_url { 'https://example.com/dashboard' }
    ip_address { '192.168.1.1' }
    user_agent { 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' }
    used { false }
    expires_at { 2.minutes.from_now }

    trait :used do
      used { true }
    end

    trait :expired do
      expires_at { 1.hour.ago }
    end

    trait :valid do
      used { false }
      expires_at { 1.hour.from_now }
    end
  end
end
