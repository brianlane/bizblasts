# frozen_string_literal: true

FactoryBot.define do
  factory :csv_import_run do
    association :business
    import_type { 'customers' }
    original_filename { 'test-import.csv' }
    status { :queued }

    after(:build) do |import_run|
      unless import_run.csv_file.attached?
        import_run.csv_file.attach(
          io: StringIO.new("email,first_name,last_name\ntest@example.com,John,Doe"),
          filename: import_run.original_filename || 'test.csv',
          content_type: 'text/csv'
        )
      end
    end

    trait :running do
      status { :running }
      started_at { Time.current }
      total_rows { 10 }
    end

    trait :succeeded do
      status { :succeeded }
      started_at { 1.hour.ago }
      finished_at { Time.current }
      total_rows { 10 }
      processed_rows { 10 }
      created_count { 8 }
      updated_count { 2 }
    end

    trait :failed do
      status { :failed }
      started_at { 1.hour.ago }
      finished_at { Time.current }
      total_rows { 10 }
      processed_rows { 3 }
      error_count { 7 }
      error_report { { errors: [{ row: 4, message: 'Invalid email' }] } }
    end

    trait :partial do
      status { :partial }
      started_at { 1.hour.ago }
      finished_at { Time.current }
      total_rows { 10 }
      processed_rows { 10 }
      created_count { 7 }
      error_count { 3 }
      error_report { { errors: [{ row: 4, message: 'Invalid email' }] } }
    end

    trait :with_user do
      association :user, factory: [:user, :manager]
    end
  end
end

