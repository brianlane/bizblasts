# frozen_string_literal: true

FactoryBot.define do
  factory :booking do
    # Simple and consistent values
    start_time { Time.zone.now + 1.day }
    end_time { Time.zone.now + 1.day + 1.hour }
    status { 'confirmed' }
    notes { 'Test booking' }
    
    # Use build strategy for associations by default (can be overridden in specs)
    association :business, strategy: :build
    association :service, strategy: :build
    association :staff_member, strategy: :build
    association :tenant_customer, strategy: :build
  end
end 