# frozen_string_literal: true

FactoryBot.define do
  factory :service_job_form do
    association :service
    association :job_form_template
    required { false }
    timing { :before_service }

    trait :required do
      required { true }
    end

    trait :during_service do
      timing { :during_service }
    end

    trait :after_service do
      timing { :after_service }
    end
  end
end
