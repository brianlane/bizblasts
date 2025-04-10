FactoryBot.define do
  factory :template_page_section do
    # service_template_page is optional now
    section_type { :text }
    content { "Sample content for a template section" }
    sequence(:position) { |n| n }
    active { true }
  end
end
