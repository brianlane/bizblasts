FactoryBot.define do
  factory :page_version do
    page
    created_by factory: :user
    version_number { 1 }
    content_snapshot do
      {
        page_attributes: page.attributes,
        sections: page.page_sections.map(&:attributes),
        theme_settings: {},
        timestamp: Time.current
      }
    end
    status { 'draft' }
    change_notes { 'Initial version' }

    trait :published do
      status { 'published' }
      published_at { Time.current }
    end

    trait :archived do
      status { 'archived' }
    end

    trait :with_notes do
      change_notes { Faker::Lorem.sentence }
    end

    # Sequence for version numbers within the same page
    sequence :version_number do |n|
      n
    end
  end
end 