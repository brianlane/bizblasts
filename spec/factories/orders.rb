FactoryBot.define do
  factory :order do
    association :tenant_customer # Assuming you have a tenant_customer factory scoped to business
    association :business
    association :shipping_method, factory: :shipping_method # Create associated shipping method if not provided
    association :tax_rate, factory: :tax_rate # Create associated tax rate if not provided

    status { Order.statuses.keys.sample } # Random status
    shipping_address { "123 Shipping St" }
    billing_address { "456 Billing Ave" }
    notes { "Order notes here" }

    # Set associations based on tenant_customer's business if not explicitly provided
    # But skip for business_deleted status
    after(:build) do |order|
      # Skip association setup for business_deleted orders
      unless order.status == 'business_deleted'
        order.business ||= order.tenant_customer&.business
        # Ensure associated methods belong to the same business
        order.shipping_method = create(:shipping_method, business: order.business) unless order.shipping_method&.business == order.business
        order.tax_rate = create(:tax_rate, business: order.business) unless order.tax_rate&.business == order.business
      end
    end

    # Set calculated fields *after* associations are finalized but before validation
    # Note: Total calculation happens in before_save callback in the model
    # We just need placeholder values to pass initial validation if required
    total_amount { 99.99 } # Placeholder, will be recalculated
    tax_amount { 9.99 }    # Placeholder
    shipping_amount { 5.99 } # Placeholder

    trait :pending_payment do
      status { :pending_payment }
    end

    trait :paid do
      status { :paid }
    end

    trait :processing do
      status { :processing }
    end

    trait :shipped do
      status { :shipped }
    end

    trait :cancelled do
      status { :cancelled }
    end

    trait :refunded do
      status { :refunded }
    end

    trait :business_deleted do
      status { :business_deleted }
      tenant_customer { nil }
      business { nil }
      shipping_method { nil }
      tax_rate { nil }
    end

    # Trait to create line items
    transient do
      line_items_count { 0 }
      # Optionally pass specific product variants to use
      # variants_for_items { [] }
    end

    after(:build) do |order, evaluator|
      # Must happen *after* business is set and skip for business_deleted
      if evaluator.line_items_count > 0 && order.status != 'business_deleted' && order.business.present?
        evaluator.line_items_count.times do |i|
          # Create a product and variant belonging to the order's business
          product = create(:product, business: order.business, variants_count: 1)
          variant = product.product_variants.last
          # variant = evaluator.variants_for_items[i] || create(:product_variant, product: create(:product, business: order.business))
          order.line_items << build(:line_item, lineable: order, product_variant: variant)
        end
      end
      # Trigger calculation before validation if necessary for factory state
      # order.send(:calculate_totals)
    end

    # Ensure order number is set (handled by before_validation in model)
  end
end 