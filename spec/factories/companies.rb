# frozen_string_literal: true

FactoryBot.define do
  factory :company do
    sequence(:name) { |n| "Company #{n}" }
    sequence(:subdomain) { |n| "company#{n}" }
  end
end 