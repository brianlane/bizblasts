FactoryBot.define do
  factory :staff_member do
    association :business
    name { Faker::Name.name } 
    email { Faker::Internet.unique.email }
    phone { "#{rand(200..999)}-#{rand(100..999)}-#{rand(1000..9999)}" }
    active { true }
    availability { {} } # Empty default availability

    trait :with_standard_availability do
      availability do 
        {
          "monday" => [{ "start" => "09:00", "end" => "12:00" }, { "start" => "13:00", "end" => "17:00" }],
          "tuesday" => [{ "start" => "10:00", "end" => "16:00" }],
          "wednesday" => [], # Closed
          "thursday" => [{ "start" => "09:00", "end" => "17:00" }],
          "friday" => [{ "start" => "09:00", "end" => "17:00" }],
          "exceptions" => {
            "2024-12-25" => [], # Holiday - Closed
            "2024-11-28" => [{ "start" => "10:00", "end" => "14:00" }] # Special Hours
          }
        }
      end
    end

    # availability { { monday: [{ start: '09:00', end: '17:00' }] } } # Example
    # settings { {} }
    # notes { Faker::Lorem.sentence }
  end
end 