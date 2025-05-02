FactoryBot.define do
  factory :line_item do
    # Association with a lineable (Order or Invoice)
    # This needs to be set when creating the line item, typically within the lineable factory
    # Example: association :lineable, factory: :order
    transient do
      lineable_factory { :order } # Default to order, can be overridden with :service
    end

    lineable { association(lineable_factory) }

    # Association with a product variant
    # Ensure the variant belongs to the same business as the lineable
    association :product_variant

    quantity { rand(1..5) }

    # Price and total_amount are set by callbacks in the model based on variant and quantity
    # We might not need to set them here unless testing specific scenarios
    # price { product_variant&.final_price } # Example if needed before save
    # total_amount { price * quantity if price && quantity } # Example
  end
end 