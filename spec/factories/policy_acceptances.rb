# frozen_string_literal: true

FactoryBot.define do
  factory :policy_acceptance do
    association :user
    policy_type { 'privacy_policy' }
    policy_version { 'v1.0' }
    accepted_at { Time.current }
    ip_address { '127.0.0.1' }
    user_agent { 'Test Browser' }
  end
end 