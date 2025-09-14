FactoryBot.define do
  factory :authentication_bridge do
    user { nil }
    token { "MyString" }
    expires_at { "2025-09-14 08:45:05" }
    target_url { "MyText" }
    used_at { "2025-09-14 08:45:05" }
  end
end
