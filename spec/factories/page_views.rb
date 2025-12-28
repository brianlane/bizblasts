# frozen_string_literal: true

FactoryBot.define do
  factory :page_view do
    association :business
    visitor_fingerprint { SecureRandom.hex(16) }
    session_id { SecureRandom.uuid }
    page_path { ['/', '/services', '/products', '/contact', '/about'].sample }
    page_type { ['home', 'services', 'products', 'contact', 'about', 'custom'].sample }
    page_title { "#{page_type&.titleize} Page" }
    
    referrer_url { [nil, 'https://google.com/search?q=test', 'https://facebook.com/'].sample }
    referrer_domain { referrer_url.present? ? URI.parse(referrer_url).host : nil }
    
    device_type { ['desktop', 'mobile', 'tablet'].sample }
    browser { ['Chrome', 'Firefox', 'Safari', 'Edge'].sample }
    browser_version { "#{rand(80..120)}.0" }
    os { ['Windows', 'macOS', 'iOS', 'Android', 'Linux'].sample }
    
    country { 'US' }
    region { ['CA', 'NY', 'TX', 'FL', 'WA'].sample }
    city { ['Los Angeles', 'New York', 'Houston', 'Miami', 'Seattle'].sample }
    
    time_on_page { rand(5..300) }
    scroll_depth { rand(0..100) }
    is_entry_page { false }
    is_exit_page { false }
    is_bounce { false }

    trait :entry do
      is_entry_page { true }
      page_path { '/' }
    end

    trait :exit do
      is_exit_page { true }
    end

    trait :bounce do
      is_bounce { true }
      is_entry_page { true }
      is_exit_page { true }
    end

    trait :mobile do
      device_type { 'mobile' }
      os { ['iOS', 'Android'].sample }
    end

    trait :desktop do
      device_type { 'desktop' }
      os { ['Windows', 'macOS', 'Linux'].sample }
    end

    trait :from_google do
      referrer_url { 'https://google.com/search?q=business+name' }
      referrer_domain { 'google.com' }
    end

    trait :from_facebook do
      referrer_url { 'https://facebook.com/referral' }
      referrer_domain { 'facebook.com' }
    end

    trait :direct do
      referrer_url { nil }
      referrer_domain { nil }
    end

    trait :with_utm do
      utm_source { ['google', 'facebook', 'instagram', 'email'].sample }
      utm_medium { ['cpc', 'social', 'email', 'organic'].sample }
      utm_campaign { "campaign_#{rand(1000..9999)}" }
    end
  end
end

