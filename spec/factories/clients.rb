# frozen_string_literal: true

FactoryBot.define do
  factory :client, class: 'User' do
    first_name { "Test" }
    last_name { "Client" }
    sequence(:email) { |n| "client#{n}@example.com" }
    password { "password" }
    password_confirmation { "password" }
    role { :client } # Assuming you have a role attribute/enum
    active { true } # Ensure user is active

    # Add association if clients belong to a business
    # association :business

    after(:create) do |user|
      # Ensure confirmation if using Devise confirmable module
      # user.confirm if user.respond_to?(:confirm) 
    end
  end
end 