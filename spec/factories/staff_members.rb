# frozen_string_literal: true

FactoryBot.define do
  factory :staff_member do
    association :business
    name { Faker::Name.name }
    email { Faker::Internet.unique.email }
    # Use Faker for phone number for more realistic formats
    phone { Faker::PhoneNumber.unique.phone_number }
    active { true }
    # Default availability (Mon-Fri 9-5)
    availability do
      {
        'monday' => [{ 'start' => '09:00', 'end' => '17:00' }],
        'tuesday' => [{ 'start' => '09:00', 'end' => '17:00' }],
        'wednesday' => [{ 'start' => '09:00', 'end' => '17:00' }],
        'thursday' => [{ 'start' => '09:00', 'end' => '17:00' }],
        'friday' => [{ 'start' => '09:00', 'end' => '17:00' }],
        'exceptions' => {}
      }
    end

    # Trait for inactive staff member
    trait :inactive do
      active { false }
    end

    # Trait for complex availability including exceptions
    trait :with_complex_availability do
      availability do
        {
          monday: [{ start: '08:00', end: '12:00' }, { start: '13:00', end: '17:00' }],
          tuesday: [], # Closed
          wednesday: [{ start: '10:00', end: '15:00' }],
          # Thursday uses default
          friday: [{ start: '09:00', end: '13:00' }],
          saturday: [{ start: '10:00', end: '14:00' }],
          # Sunday uses default (empty)
          exceptions: {
            "#{Date.today.iso8601}": [{ start: '11:00', end: '14:00' }], # Special hours today
            "#{Date.tomorrow.iso8601}": [] # Closed tomorrow
          }
        }
      end
    end

    # Optional: Trait to associate with a User
    trait :with_user do
      association :user
    end
  end
end 