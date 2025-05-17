FactoryBot.define do
  factory :integration do
    association :business
    kind { Integration.kinds.keys.sample } # Or a specific default like :webhook
    config { { url: "https://example.com/default_hook", key: "value" } }

    trait :google_calendar do
      kind { :google_calendar }
      config { { client_id: "gc_client_id_123", client_secret: "gc_secret_xyz", refresh_token: "gc_refresh_token" } }
    end

    trait :zapier do
      kind { :zapier }
      config { { api_key: "zapier_api_key_abc", zap_id: "12345" } }
    end

    trait :webhook do
      kind { :webhook }
      config { { url: "https://example.com/webhook_endpoint", event_types: ["booking_created", "booking_updated"] } }
    end
  end
end 