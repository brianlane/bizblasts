# frozen_string_literal: true

FactoryBot.define do
  factory :email_marketing_connection do
    association :business

    trait :mailchimp do
      provider { :mailchimp }
      access_token { "mc_test_token_#{SecureRandom.hex(16)}" }
      account_id { "mc_account_#{SecureRandom.hex(8)}" }
      account_email { Faker::Internet.email }
      api_server { 'us1' }
      active { true }
      connected_at { Time.current }
    end

    trait :constant_contact do
      provider { :constant_contact }
      access_token { "cc_test_token_#{SecureRandom.hex(16)}" }
      refresh_token { "cc_refresh_token_#{SecureRandom.hex(16)}" }
      token_expires_at { 1.hour.from_now }
      account_id { "cc_account_#{SecureRandom.hex(8)}" }
      account_email { Faker::Internet.email }
      active { true }
      connected_at { Time.current }
    end

    trait :with_list do
      default_list_id { SecureRandom.hex(10) }
      default_list_name { 'Main Newsletter' }
    end

    trait :inactive do
      active { false }
    end

    trait :expired_token do
      token_expires_at { 1.hour.ago }
    end

    trait :sync_enabled do
      sync_on_customer_create { true }
      sync_on_customer_update { true }
      receive_unsubscribe_webhooks { true }
    end
  end

  factory :email_marketing_sync_log do
    association :email_marketing_connection
    association :business

    sync_type { :full_sync }
    status { :pending }
    direction { :outbound }

    trait :running do
      status { :running }
      started_at { Time.current }
    end

    trait :completed do
      status { :completed }
      started_at { 5.minutes.ago }
      completed_at { Time.current }
      contacts_synced { 50 }
      contacts_created { 30 }
      contacts_updated { 20 }
    end

    trait :failed do
      status { :failed }
      started_at { 5.minutes.ago }
      completed_at { Time.current }
      contacts_failed { 10 }
      error_details { [{ message: 'API rate limit exceeded', occurred_at: Time.current.iso8601 }] }
    end

    trait :incremental do
      sync_type { :incremental }
    end

    trait :single_contact do
      sync_type { :single_contact }
    end

    trait :inbound do
      direction { :inbound }
    end
  end
end
