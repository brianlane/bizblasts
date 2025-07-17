FactoryBot.define do
  factory :service_variant do
    association :service
    name { ["30 min", "60 min", "90 min", "Express", "Standard", "Premium"].sample + " #{SecureRandom.hex(2)}" }
    duration { [30, 45, 60, 90, 120].sample }
    price { [50.0, 75.0, 100.0, 125.0, 150.0].sample }
    position { 1 }
    active { true }

    # Ensure business consistency via service
    # No direct business association needed here if delegated correctly
  end
end 