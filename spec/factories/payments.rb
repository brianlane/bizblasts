FactoryBot.define do
  factory :payment do
    association :business
    association :invoice
    association :tenant_customer
    order { nil }

    amount { invoice.total_amount }
    platform_fee_amount { 0.0 }
    stripe_fee_amount { 0.0 }
    business_amount { amount - (platform_fee_amount + stripe_fee_amount) }

    stripe_payment_intent_id { "pi_#{SecureRandom.hex(8)}" }
    stripe_charge_id { "ch_#{SecureRandom.hex(8)}" }
    stripe_customer_id { tenant_customer.stripe_customer_id || "cus_#{SecureRandom.hex(8)}" }
    stripe_transfer_id { "tr_#{SecureRandom.hex(8)}" }

    payment_method { :credit_card }
    status { :pending }
    paid_at { nil }
    failure_reason { nil }
    refunded_amount { 0.0 }
    refund_reason { nil }
  end
end 