FactoryBot.define do
  factory :customer do
    association :business
    name { Faker::Name.name }
    email { Faker::Internet.unique.email }
    phone { Faker::PhoneNumber.phone_number }
  end
end
