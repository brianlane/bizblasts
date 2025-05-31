# frozen_string_literal: true

FactoryBot.define do
  factory :policy_version do
    policy_type { 'privacy_policy' }
    sequence(:version) { |n| "v1.#{n}" }
    active { false }
    requires_notification { false }
    effective_date { Date.current }
    change_summary { 'Test policy change' }
    termly_embed_id { '12345678-1234-1234-1234-123456789012' }
  end
end 