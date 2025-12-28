# frozen_string_literal: true

FactoryBot.define do
  factory :click_event do
    association :business
    visitor_fingerprint { SecureRandom.hex(16) }
    session_id { SecureRandom.uuid }
    element_type { 'button' }
    element_identifier { "btn-#{rand(1000..9999)}" }
    element_text { ['Book Now', 'Learn More', 'Contact Us', 'View Services', 'Add to Cart'].sample }
    page_path { ['/', '/services', '/products', '/contact'].sample }
    page_title { 'Test Page' }
    category { 'booking' }
    action { 'click' }
    
    is_conversion { false }
    conversion_value { nil }

    trait :booking_click do
      category { 'booking' }
      element_type { 'button' }
      element_text { 'Book Now' }
      action { 'book' }
    end

    trait :product_click do
      category { 'product' }
      element_type { 'card' }
      action { 'view' }
      target_type { 'Product' }
      target_id { rand(1..100) }
    end

    trait :service_click do
      category { 'service' }
      element_type { 'link' }
      action { 'view' }
      target_type { 'Service' }
      target_id { rand(1..100) }
    end

    trait :contact_click do
      category { 'contact' }
      element_type { 'form_submit' }
      action { 'submit' }
    end

    trait :phone_click do
      category { 'phone' }
      element_type { 'link' }
      action { 'call' }
    end

    trait :social_click do
      category { 'social' }
      element_type { 'link' }
      action { 'click' }
      element_text { ['Facebook', 'Instagram', 'Twitter'].sample }
    end

    trait :conversion do
      is_conversion { true }
      conversion_type { ['booking_completed', 'purchase', 'estimate_request'].sample }
      conversion_value { rand(25..500).to_d }
    end

    trait :booking_started do
      is_conversion { true }
      conversion_type { 'booking_started' }
      conversion_value { 0 }
    end

    trait :booking_completed do
      is_conversion { true }
      conversion_type { 'booking_completed' }
      conversion_value { rand(50..200).to_d }
    end

    trait :with_position do
      click_x { rand(0..1920) }
      click_y { rand(0..1080) }
      viewport_width { 1920 }
      viewport_height { 1080 }
    end
  end
end

