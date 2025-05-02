FactoryBot.define do
  factory :invoice do
    association :business
    association :tenant_customer # Use correct association
    # association :booking, optional: true
    # promotion is optional, set via service
    
    sequence(:invoice_number) { |n| "INV-#{Time.current.year}-#{n.to_s.rjust(4, '0')}" }
    due_date { 1.month.from_now }
    amount { 100.00 } # Default amount, adjust as needed
    tax_amount { 0.00 }
    total_amount { amount + tax_amount }
    status { :pending }
    # original_amount, discount_amount are set by PromotionManager

    trait :with_booking do
      association :booking
      # Optionally link amount to booking/service price
      after(:build) do |invoice, evaluator|
        if invoice.booking && invoice.amount.blank?
          invoice.amount = invoice.booking.service&.price || 100.00
          invoice.total_amount = invoice.amount + invoice.tax_amount
        end
      end
    end

    trait :paid do
      status { :paid }
    end

    trait :overdue do
      status { :overdue }
      due_date { 1.week.ago }
    end
  end
end 