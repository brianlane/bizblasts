FactoryBot.define do
  factory :integration_credential do
    business
    provider { "plivo" }  # Default to plivo now that we've implemented it
    config { { auth_id: "test_auth_id", auth_token: "test_auth_token", source_number: "+15551234567" } }

    trait :twilio do
      provider { "twilio" }
      config { { account_sid: "test_sid", auth_token: "test_token", phone_number: "+15551234567" } }
    end

    trait :plivo do
      provider { "plivo" }
      config { { auth_id: "test_auth_id", auth_token: "test_auth_token", source_number: "+15551234567" } }
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