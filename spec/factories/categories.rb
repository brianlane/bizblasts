FactoryBot.define do
  factory :category do
    name { "Category #{SecureRandom.hex(3)}" }
    association :business # Assuming you have a business factory

    # Add trait if needed, e.g., for categories with products
    # trait :with_products do
    #   after(:create) do |category, evaluator|
    #     create_list(:product, 3, category: category, business: category.business)
    #   end
    # end
  end
end 