FactoryBot.define do
  factory :booking_product_add_on do
    association :booking
    association :product_variant
    quantity { 1 }
    
    # Price and total_amount will be set by the model's before_validation callback
    # but we can provide defaults for testing
    price { product_variant&.final_price || 10.00 }
    total_amount { (price || 10.00) * quantity }
    
    trait :with_quantity do
      transient do
        addon_quantity { 2 }
      end
      
      quantity { addon_quantity }
      total_amount { (price || 10.00) * quantity }
    end
  end
end 