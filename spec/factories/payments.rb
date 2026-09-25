FactoryBot.define do
  factory :payment do
    business do
      if __override_names__.include?(:invoice) && invoice&.business
        invoice.business
      elsif __override_names__.include?(:order) && order&.business
        order.business
      elsif __override_names__.include?(:tenant_customer) && tenant_customer&.business
        tenant_customer.business
      else
        ActsAsTenant.current_tenant || association(:business)
      end
    end
    tenant_customer do
      if __override_names__.include?(:invoice) && invoice&.tenant_customer
        invoice.tenant_customer
      elsif __override_names__.include?(:tenant_customer)
        tenant_customer
      else
        association(:tenant_customer, business: business)
      end
    end
    invoice { association :invoice, business: business, tenant_customer: tenant_customer }
    order { nil }

    amount { invoice.total_amount }
    platform_fee_amount do
      amount_cents = (amount * 100).to_i
      platform_fee_rate = business&.platform_fee_rate || BizBlasts::PLATFORM_FEE_RATE
      (amount_cents * platform_fee_rate).round / 100.0
    end
    stripe_fee_amount do
      amount_cents = (amount * 100).to_i
      ((amount_cents * 0.029).round + 30) / 100.0
    end
    # In direct charges, business pays Stripe fees, so we only deduct platform fee
    business_amount { amount - stripe_fee_amount - platform_fee_amount }

    stripe_payment_intent_id { "pi_#{SecureRandom.hex(8)}" }
    stripe_charge_id { "ch_#{SecureRandom.hex(8)}" }
    stripe_customer_id { tenant_customer.stripe_customer_id || "cus_#{SecureRandom.hex(8)}" }
    stripe_transfer_id { "tr_#{SecureRandom.hex(8)}" }

    payment_method { :credit_card }
    status { :completed }
    paid_at { Time.current }
    failure_reason { nil }
    refunded_amount { 0.0 }
    refund_reason { nil }
    tip_received_on_initial_payment { false }
    tip_amount_received_initially { 0.0 }
    
    trait :pending do
      status { :pending }
      paid_at { nil }
    end
    
    trait :failed do
      status { :failed }
      paid_at { nil }
      failure_reason { "Card declined" }
    end
  end
end 