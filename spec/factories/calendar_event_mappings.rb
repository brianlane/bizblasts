# frozen_string_literal: true

FactoryBot.define do
  factory :calendar_event_mapping do
    booking
    calendar_connection
    external_event_id { "event_#{SecureRandom.hex(8)}" }
    external_calendar_id { 'primary' }
    status { 'synced' }
    last_synced_at { Time.current }
    
    trait :pending do
      status { 'pending' }
      last_synced_at { nil }
    end
    
    trait :failed do
      status { 'failed' }
      last_error { 'API Error: Rate limit exceeded' }
    end
    
    trait :deleted do
      status { 'deleted' }
    end
  end
end