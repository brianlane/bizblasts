FactoryBot.define do
  factory :page_section do
    association :page
    section_type { :text }
    content { "Sample content for a page section" }
    sequence(:position) { |n| n }
    active { true }
  end
end
