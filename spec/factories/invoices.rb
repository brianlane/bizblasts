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
      # Ensure business has a default tax rate for proper tax calculation
      after(:build) do |invoice, evaluator|
        # Create default tax rate if business doesn't have one
        unless invoice.business.default_tax_rate
          create(:tax_rate, business: invoice.business, name: 'Default Tax', rate: 0.098)
        end
        
        # Assign the default tax rate to the invoice
        invoice.tax_rate = invoice.business.default_tax_rate
        
        # Let the invoice calculate its own totals based on booking
        if invoice.booking
          # Don't set amount manually - let calculate_totals handle it
          invoice.amount = nil
          invoice.tax_amount = nil
          invoice.total_amount = nil
        end
      end
    end

    trait :with_tax_rate do
      association :tax_rate
      after(:build) do |invoice, evaluator|
        # Ensure tax_rate belongs to the same business
        invoice.tax_rate.business = invoice.business
        invoice.tax_rate.save! if invoice.tax_rate.changed?
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