FactoryBot.define do
  factory :integration_credential do
    business
    provider { "twilio" }  # Default to twilio now that we've migrated
    config { { account_sid: "test_sid", auth_token: "test_token", messaging_service_sid: "test_service_sid" } }

    trait :twilio do
      provider { "twilio" }
      config { { account_sid: "test_sid", auth_token: "test_token", messaging_service_sid: "test_service_sid" } }
    end

    trait :mailgun do
      provider { "mailgun" }
      config { { api_key: "test_key", domain: "test.mailgun.org" } }
    end

    trait :sendgrid do
      provider { "sendgrid" }
      config { { api_key: "test_sendgrid_key" } }
    end
  end
end 