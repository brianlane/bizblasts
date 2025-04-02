FactoryBot.define do
  factory :service do
    association :company
    name { Faker::Company.bs.capitalize }
    description { Faker::Lorem.sentence }
    duration_minutes { [30, 60, 90, 120].sample }
    price { Faker::Commerce.price(range: 10..500.0) }
    active { true }
  end
end
