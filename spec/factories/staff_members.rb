# frozen_string_literal: true

FactoryBot.define do
  factory :staff_member do
    name { Faker::Name.name }
    email { Faker::Internet.email }
    phone { Faker::PhoneNumber.phone_number }
    bio { Faker::Lorem.paragraph }
    active { true }
    position { Faker::Job.title }
    association :business
    
    availability do
      {
        'monday' => [{ 'start' => '09:00', 'end' => '17:00' }],
        'tuesday' => [{ 'start' => '09:00', 'end' => '17:00' }],
        'wednesday' => [{ 'start' => '09:00', 'end' => '17:00' }],
        'thursday' => [{ 'start' => '09:00', 'end' => '17:00' }],
        'friday' => [{ 'start' => '09:00', 'end' => '17:00' }],
        'saturday' => [],
        'sunday' => [],
        'exceptions' => {}
      }
    end
    
    trait :inactive do
      active { false }
    end
    
    trait :weekend_available do
      availability do
        {
          'monday' => [{ 'start' => '09:00', 'end' => '17:00' }],
          'tuesday' => [{ 'start' => '09:00', 'end' => '17:00' }],
          'wednesday' => [{ 'start' => '09:00', 'end' => '17:00' }],
          'thursday' => [{ 'start' => '09:00', 'end' => '17:00' }],
          'friday' => [{ 'start' => '09:00', 'end' => '17:00' }],
          'saturday' => [{ 'start' => '10:00', 'end' => '16:00' }],
          'sunday' => [{ 'start' => '10:00', 'end' => '14:00' }],
          'exceptions' => {}
        }
      end
    end
    
    trait :split_shifts do
      availability do
        {
          'monday' => [
            { 'start' => '09:00', 'end' => '12:00' },
            { 'start' => '13:00', 'end' => '17:00' }
          ],
          'tuesday' => [
            { 'start' => '09:00', 'end' => '12:00' },
            { 'start' => '13:00', 'end' => '17:00' }
          ],
          'wednesday' => [
            { 'start' => '09:00', 'end' => '12:00' },
            { 'start' => '13:00', 'end' => '17:00' }
          ],
          'thursday' => [
            { 'start' => '09:00', 'end' => '12:00' },
            { 'start' => '13:00', 'end' => '17:00' }
          ],
          'friday' => [
            { 'start' => '09:00', 'end' => '12:00' },
            { 'start' => '13:00', 'end' => '17:00' }
          ],
          'saturday' => [],
          'sunday' => [],
          'exceptions' => {}
        }
      end
    end
    
    trait :with_exception do
      availability do
        {
          'monday' => [{ 'start' => '09:00', 'end' => '17:00' }],
          'tuesday' => [{ 'start' => '09:00', 'end' => '17:00' }],
          'wednesday' => [{ 'start' => '09:00', 'end' => '17:00' }],
          'thursday' => [{ 'start' => '09:00', 'end' => '17:00' }],
          'friday' => [{ 'start' => '09:00', 'end' => '17:00' }],
          'saturday' => [],
          'sunday' => [],
          'exceptions' => {
            Date.today.to_s => [{ 'start' => '10:00', 'end' => '14:00' }]
          }
        }
      end
    end

    trait :with_complex_availability do
      availability do
        {
          'monday' => [
            { 'start' => '08:00', 'end' => '12:00' },
            { 'start' => '13:00', 'end' => '17:00' }
          ],
          'tuesday' => [], # Closed
          'wednesday' => [{ 'start' => '09:00', 'end' => '17:00' }],
          'thursday' => [{ 'start' => '09:00', 'end' => '17:00' }],
          'friday' => [{ 'start' => '09:00', 'end' => '17:00' }],
          'saturday' => [{ 'start' => '10:00', 'end' => '15:00' }],
          'sunday' => [], # Closed
          'exceptions' => {
            Date.today.to_s => [{ 'start' => '11:30', 'end' => '14:00' }],
            (Date.today + 1).to_s => [] # Closed for holiday
          }
        }
      end
    end
  end
end