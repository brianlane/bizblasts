# frozen_string_literal: true

FactoryBot.define do
  factory :job_attachment do
    association :business
    attachable { association :service }
    attachment_type { :before_photo }
    title { Faker::Lorem.words(number: 3).join(' ').titleize }
    description { Faker::Lorem.paragraph }
    instructions { Faker::Lorem.paragraph }
    visibility { :internal }
    position { nil }

    trait :after_photo do
      attachment_type { :after_photo }
    end

    trait :instruction do
      attachment_type { :instruction }
    end

    trait :reference_file do
      attachment_type { :reference_file }
    end

    trait :general do
      attachment_type { :general }
    end

    trait :customer_visible do
      visibility { :customer_visible }
    end

    trait :for_booking do
      attachable { association :booking }
    end

    trait :for_estimate do
      attachable { association :estimate }
    end

    trait :with_uploaded_by do
      association :uploaded_by_user, factory: :user
    end
  end
end
