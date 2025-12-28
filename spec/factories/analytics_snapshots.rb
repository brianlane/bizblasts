# frozen_string_literal: true

FactoryBot.define do
  factory :analytics_snapshot do
    association :business
    snapshot_type { 'daily' }
    period_start { Date.current }
    period_end { Date.current }
    generated_at { Time.current }
    
    unique_visitors { rand(10..500) }
    total_page_views { rand(50..2000) }
    total_sessions { rand(15..600) }
    bounce_rate { rand(20..70).to_d }
    avg_session_duration { rand(60..300) }
    pages_per_session { rand(1.5..5.0).round(2) }
    
    total_conversions { rand(0..50) }
    conversion_rate { rand(1..15).to_d }
    total_conversion_value { rand(100..5000).to_d }
    
    booking_metrics do
      {
        total: rand(5..50),
        completed: rand(3..40),
        cancelled: rand(0..5),
        revenue: rand(500..5000),
        avg_value: rand(50..200)
      }
    end
    
    product_metrics do
      {
        views: rand(20..200),
        purchases: rand(1..30),
        revenue: rand(100..3000),
        conversion_rate: rand(1..10)
      }
    end
    
    service_metrics do
      {
        views: rand(30..300),
        bookings: rand(5..50),
        conversion_rate: rand(5..25)
      }
    end
    
    estimate_metrics do
      {
        sent: rand(5..30),
        viewed: rand(3..25),
        approved: rand(1..15),
        total_value: rand(1000..10000),
        conversion_rate: rand(10..50)
      }
    end
    
    traffic_sources do
      {
        direct: rand(20..40),
        organic: rand(30..50),
        referral: rand(5..15),
        social: rand(5..20),
        paid: rand(0..10)
      }
    end
    
    top_referrers do
      [
        { domain: 'google.com', visits: rand(50..200) },
        { domain: 'facebook.com', visits: rand(10..50) },
        { domain: 'yelp.com', visits: rand(5..30) }
      ]
    end
    
    top_pages do
      [
        { path: '/', views: rand(100..500), avg_time: rand(30..120) },
        { path: '/services', views: rand(50..200), avg_time: rand(45..180) },
        { path: '/contact', views: rand(20..100), avg_time: rand(60..240) }
      ]
    end
    
    device_breakdown do
      { desktop: rand(50..70), mobile: rand(25..40), tablet: rand(5..10) }
    end
    
    geo_breakdown do
      { 'US' => rand(70..90), 'CA' => rand(5..15), 'UK' => rand(2..8) }
    end

    trait :daily do
      snapshot_type { 'daily' }
      period_start { Date.current }
      period_end { Date.current }
    end

    trait :weekly do
      snapshot_type { 'weekly' }
      period_start { Date.current.beginning_of_week }
      period_end { Date.current.end_of_week }
    end

    trait :monthly do
      snapshot_type { 'monthly' }
      period_start { Date.current.beginning_of_month }
      period_end { Date.current.end_of_month }
    end

    trait :yesterday do
      period_start { Date.yesterday }
      period_end { Date.yesterday }
    end

    trait :last_week do
      snapshot_type { 'weekly' }
      period_start { 1.week.ago.to_date.beginning_of_week }
      period_end { 1.week.ago.to_date.end_of_week }
    end

    trait :high_traffic do
      unique_visitors { rand(1000..5000) }
      total_page_views { rand(5000..20000) }
      total_sessions { rand(1200..6000) }
    end

    trait :low_traffic do
      unique_visitors { rand(1..50) }
      total_page_views { rand(5..100) }
      total_sessions { rand(2..60) }
    end

    trait :high_conversion do
      conversion_rate { rand(15..30).to_d }
      total_conversions { rand(50..200) }
      total_conversion_value { rand(5000..20000).to_d }
    end
  end
end

