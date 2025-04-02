FactoryBot.define do
  factory :service_provider do
    association :company
    name { Faker::Name.name } 
    email { Faker::Internet.unique.email }
    phone { Faker::PhoneNumber.phone_number }
    active { true }
    # availability { { monday: [{ start: '09:00', end: '17:00' }] } } # Example
    # settings { {} }
    # notes { Faker::Lorem.sentence }
  end
end 