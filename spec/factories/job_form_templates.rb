# frozen_string_literal: true

FactoryBot.define do
  factory :job_form_template do
    association :business
    name { Faker::Lorem.words(number: 3).join(' ').titleize }
    description { Faker::Lorem.paragraph }
    form_type { :checklist }
    active { false }  # Default to inactive to avoid requiring fields
    position { nil }
    fields { { 'fields' => [] } }

    trait :active do
      active { true }
    end

    trait :inactive do
      active { false }
    end

    trait :inspection do
      form_type { :inspection }
    end

    trait :completion_report do
      form_type { :completion_report }
    end

    trait :custom do
      form_type { :custom }
    end

    trait :with_fields do
      fields do
        {
          'fields' => [
            {
              'id' => SecureRandom.uuid,
              'type' => 'checkbox',
              'label' => 'Equipment checked',
              'required' => true,
              'position' => 0
            },
            {
              'id' => SecureRandom.uuid,
              'type' => 'text',
              'label' => 'Notes',
              'required' => false,
              'position' => 1,
              'placeholder' => 'Add any additional notes...'
            },
            {
              'id' => SecureRandom.uuid,
              'type' => 'select',
              'label' => 'Condition',
              'required' => true,
              'position' => 2,
              'options' => %w[Excellent Good Fair Poor]
            }
          ]
        }
      end
    end

    trait :with_photo_field do
      fields do
        {
          'fields' => [
            {
              'id' => SecureRandom.uuid,
              'type' => 'photo',
              'label' => 'Before Photo',
              'required' => true,
              'position' => 0
            },
            {
              'id' => SecureRandom.uuid,
              'type' => 'photo',
              'label' => 'After Photo',
              'required' => true,
              'position' => 1
            }
          ]
        }
      end
    end

    trait :with_signature_field do
      fields do
        {
          'fields' => [
            {
              'id' => SecureRandom.uuid,
              'type' => 'signature',
              'label' => 'Customer Signature',
              'required' => true,
              'position' => 0
            }
          ]
        }
      end
    end

    # Convenience trait for active templates with fields (most common use case)
    trait :active_with_fields do
      active { true }
      fields do
        {
          'fields' => [
            {
              'id' => SecureRandom.uuid,
              'type' => 'checkbox',
              'label' => 'Task completed',
              'required' => true,
              'position' => 0
            }
          ]
        }
      end
    end
  end
end
