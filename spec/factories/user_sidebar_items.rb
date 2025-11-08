FactoryBot.define do
  factory :user_sidebar_item do
    association :user
    item_key { 'dashboard' }
    position { 0 }
    visible { true }
  end
end
