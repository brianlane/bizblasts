# frozen_string_literal: true

FactoryBot.define do
  factory :services_staff_member do
    association :service
    association :staff_member
  end
end 