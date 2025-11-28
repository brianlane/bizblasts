FactoryBot.define do
  factory :estimate_version do
    association :estimate
    version_number { 1 }
    snapshot do
      {
        estimate: estimate.attributes,
        items: estimate.estimate_items.map(&:attributes),
        created_at: Time.current.iso8601
      }
    end
    change_notes { "Initial version" }

    trait :with_changes do
      version_number { 2 }
      change_notes { "Updated pricing" }
    end
  end
end

