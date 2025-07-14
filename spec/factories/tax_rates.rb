FactoryBot.define do
  factory :tax_rate do
    sequence(:name) { |n| "Tax #{n}" }
    rate { rand(0.01..0.15).round(4) } # e.g., 1% to 15%
    region { [nil, "CA", "NY", "TX"].sample }
    applies_to_shipping { [true, false].sample }
    association :business # Assuming you have a business factory
  end
end 