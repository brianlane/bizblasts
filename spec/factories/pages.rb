FactoryBot.define do
  factory :page do
    association :business
    title { "Sample Page" }
    sequence(:slug) { |n| "sample-page-#{n}" }
    page_type { :custom }
    published { true }
    published_at { Time.current }
    menu_order { 1 }
    show_in_menu { true }
    meta_description { "A sample page for testing" }
  end
end 