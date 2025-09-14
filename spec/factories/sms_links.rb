FactoryBot.define do
  factory :sms_link do
    original_url { "MyText" }
    short_code { "MyString" }
    click_count { 1 }
    tracking_params { "" }
    last_clicked_at { "2025-09-13 09:17:58" }
  end
end
