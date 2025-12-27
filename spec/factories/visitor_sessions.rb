# frozen_string_literal: true

FactoryBot.define do
  factory :visitor_session do
    association :business
    visitor_fingerprint { SecureRandom.hex(16) }
    session_id { SecureRandom.uuid }
    session_start { rand(1..60).minutes.ago }
    session_end { nil }
    
    duration_seconds { 0 }
    page_view_count { rand(1..10) }
    click_count { rand(0..20) }
    pages_visited { page_view_count }
    
    is_bounce { false }
    
    entry_page { '/' }
    exit_page { nil }
    
    device_type { ['desktop', 'mobile', 'tablet'].sample }
    browser { ['Chrome', 'Firefox', 'Safari', 'Edge'].sample }
    os { ['Windows', 'macOS', 'iOS', 'Android'].sample }
    
    country { 'US' }
    region { 'CA' }
    city { 'Los Angeles' }
    
    converted { false }
    is_returning_visitor { false }
    previous_session_count { 0 }

    trait :active do
      session_end { nil }
      session_start { rand(1..30).minutes.ago }
    end

    trait :completed do
      session_end { Time.current }
      duration_seconds { rand(30..600) }
    end

    trait :bounce do
      is_bounce { true }
      page_view_count { 1 }
      pages_visited { 1 }
      duration_seconds { rand(1..30) }
    end

    trait :engaged do
      is_bounce { false }
      page_view_count { rand(3..15) }
      duration_seconds { rand(120..900) }
    end

    trait :converted_booking do
      converted { true }
      conversion_type { 'booking' }
      conversion_value { rand(50..200).to_d }
      conversion_time { Time.current }
    end

    trait :converted_purchase do
      converted { true }
      conversion_type { 'purchase' }
      conversion_value { rand(25..500).to_d }
      conversion_time { Time.current }
    end

    trait :returning do
      is_returning_visitor { true }
      previous_session_count { rand(1..10) }
    end

    trait :new_visitor do
      is_returning_visitor { false }
      previous_session_count { 0 }
    end

    trait :from_google do
      first_referrer_url { 'https://google.com/search?q=business' }
      first_referrer_domain { 'google.com' }
      utm_source { 'google' }
      utm_medium { 'organic' }
    end

    trait :from_facebook do
      first_referrer_url { 'https://facebook.com/' }
      first_referrer_domain { 'facebook.com' }
      utm_source { 'facebook' }
      utm_medium { 'social' }
    end

    trait :direct do
      first_referrer_url { nil }
      first_referrer_domain { nil }
      utm_source { nil }
      utm_medium { nil }
    end

    trait :mobile do
      device_type { 'mobile' }
      os { ['iOS', 'Android'].sample }
    end

    trait :desktop do
      device_type { 'desktop' }
      os { ['Windows', 'macOS'].sample }
    end
  end
end

