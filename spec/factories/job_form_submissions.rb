# frozen_string_literal: true

FactoryBot.define do
  factory :job_form_submission do
    business { ActsAsTenant.current_tenant || association(:business) }
    booking { association :booking, business: business }
    job_form_template { association :job_form_template, business: business }
    staff_member { association :staff_member, business: business }
    responses { {} }
    status { :draft }

    trait :submitted do
      status { :submitted }
      submitted_at { Time.current }
      association :submitted_by_user, factory: :user

      # Automatically fill required fields to pass validation
      after(:build) do |submission|
        template_fields = submission.job_form_template&.form_fields || []
        required_fields = template_fields.select { |f| f['required'] }

        required_fields.each do |field|
          next if submission.responses[field['id']].present?

          case field['type']
          when 'checkbox'
            submission.responses[field['id']] = true
          when 'text', 'textarea'
            submission.responses[field['id']] = 'Test response'
          when 'number'
            submission.responses[field['id']] = 1
          when 'select'
            submission.responses[field['id']] = field['options']&.first || 'Option 1'
          when 'date'
            submission.responses[field['id']] = Date.current.to_s
          when 'time'
            submission.responses[field['id']] = '10:00'
          end
        end
      end
    end

    trait :approved do
      status { :approved }
      submitted_at { 1.hour.ago }
      approved_at { Time.current }
      association :submitted_by_user, factory: :user
      association :approved_by_user, factory: :user
    end

    trait :requires_revision do
      status { :requires_revision }
      submitted_at { 1.hour.ago }
      notes { 'Please add more details to the notes section.' }
      association :submitted_by_user, factory: :user
      association :approved_by_user, factory: :user
    end

    trait :with_responses do
      transient do
        template_fields { [] }
      end

      after(:build) do |submission, evaluator|
        if evaluator.template_fields.present?
          evaluator.template_fields.each do |field|
            case field['type']
            when 'checkbox'
              submission.responses[field['id']] = true
            when 'text', 'textarea'
              submission.responses[field['id']] = Faker::Lorem.sentence
            when 'number'
              submission.responses[field['id']] = rand(1..100)
            when 'select'
              submission.responses[field['id']] = field['options']&.sample || 'Option 1'
            when 'date'
              submission.responses[field['id']] = Date.current.to_s
            when 'time'
              submission.responses[field['id']] = '10:00'
            end
          end
        end
      end
    end
  end
end
