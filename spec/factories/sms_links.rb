FactoryBot.define do
  factory :sms_link do
    original_url { 'https://example.com/resource' }
    short_code { SecureRandom.alphanumeric(8).downcase }
    click_count { 0 }
    tracking_params { {} }
    last_clicked_at { nil }
  end
end
