FactoryBot.define do
  factory :authentication_bridge do
    association :user
    token { SecureRandom.hex(32) }
    expires_at { 5.minutes.from_now }
    target_url { "https://example.com/path" }
    source_ip { "192.168.1.1" }
    user_agent { "Mozilla/5.0 (Test)" }
    used_at { nil }  # Start as unused
    
    # Trait for used tokens
    trait :used do
      used_at { 1.minute.ago }
    end
    
    # Trait for expired tokens
    trait :expired do
      expires_at { 1.hour.ago }
    end
    
    # Trait for expired and used tokens
    trait :expired_and_used do
      expires_at { 1.hour.ago }
      used_at { 2.hours.ago }
    end
  end
end
