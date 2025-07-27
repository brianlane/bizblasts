# frozen_string_literal: true

FactoryBot.define do
  factory :calendar_connection do
    business
    staff_member
    provider { 'google' }
    uid { "calendar_#{SecureRandom.hex(8)}" }
    access_token { SecureRandom.hex(32) }
    refresh_token { SecureRandom.hex(32) }
    token_expires_at { 1.hour.from_now }
    scopes { 'https://www.googleapis.com/auth/calendar' }
    connected_at { Time.current }
    active { true }
    
    trait :google do
      provider { 'google' }
      scopes { 'https://www.googleapis.com/auth/calendar' }
    end
    
    trait :microsoft do
      provider { 'microsoft' }
      scopes { 'https://graph.microsoft.com/Calendars.ReadWrite offline_access' }
    end
    
    trait :inactive do
      active { false }
    end
    
    trait :expired do
      token_expires_at { 1.hour.ago }
    end
  end
end