FactoryBot.define do
  factory :product_variant do
    association :product
    name { ["Small", "Medium", "Large", "Red", "Blue", "Green"].sample + " #{SecureRandom.hex(2)}" }
    price_modifier { [nil, -5.00, 0.00, 10.00, 2.50].sample }
    stock_quantity { 100 }

    # Ensure business consistency via product
    # No direct business association needed here if delegated correctly
  end
end 