# frozen_string_literal: true

FactoryBot.define do
  factory :rental_condition_report do
    association :rental_booking
    association :staff_member
    
    report_type { 'checkout' }
    condition_rating { 'good' }
    notes { 'Item in good condition' }
    checklist_items { [] }
    damage_assessment_amount { 0 }
    
    trait :checkout do
      report_type { 'checkout' }
    end
    
    trait :return do
      report_type { 'return' }
    end
    
    trait :with_damage do
      report_type { 'return' }
      condition_rating { 'damaged' }
      damage_assessment_amount { 25.00 }
      damage_description { 'Scratches on surface' }
      notes { 'Item returned with visible damage' }
    end
  end
end

