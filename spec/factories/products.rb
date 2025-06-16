FactoryBot.define do
  factory :product do
    name { "Product #{SecureRandom.hex(4)}" }
    description { "A description for #{name}" }
    price { rand(10.0..100.0).round(2) }
    active { true }
    featured { false }
    association :business # Assuming you have a business factory
    product_type { :standard }
    stock_quantity { 100 } # Ensure products have sufficient stock for testing

    trait :inactive do
      active { false }
    end

    trait :featured do
      featured { true }
    end

    # Trait to create variants along with the product
    transient do
      variants_count { 0 }
    end

    after(:create) do |product, evaluator|
      if evaluator.variants_count > 0
        # Pass product price to variant if modifier is not set, or ensure variant calc uses it
        # Simplified: Assume variant factory uses product.price correctly
        # If variant needs explicit base price pass: price: product.price
        create_list(:product_variant, evaluator.variants_count, product: product)
        # Ensure line_items association is reloaded if needed after variant creation
        product.reload unless product.new_record?
      end
    end

    # Trait for adding images (requires Active Storage setup in test env)
    # trait :with_images do
    #   transient do
    #     image_count { 1 }
    #   end

    #   after(:build) do |product, evaluator|
    #     evaluator.image_count.times do
    #       product.images.attach(
    #         io: File.open(Rails.root.join('spec', 'fixtures', 'files', 'test_image.png')),
    #         filename: 'test_image.png',
    #         content_type: 'image/png'
    #       )
    #     end
    #   end
    # end
  end
end 