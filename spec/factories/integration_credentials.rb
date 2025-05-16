FactoryBot.define do
  factory :integration_credential do
    business
    provider { "twilio" }
    config { { api_key: "test_key", api_secret: "test_secret" } }
  end
end 