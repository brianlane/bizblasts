FactoryBot.define do
  factory :sms_message do
    association :tenant_customer
    association :marketing_campaign
    
    phone_number { tenant_customer&.phone || "+15551234567" } 
    content { "Your appointment reminder." }
    status { :sent } 
    sent_at { 1.minute.ago }
    # delivered_at, error_message set by status methods

    trait :delivered do
      status { :delivered }
      delivered_at { Time.current }
    end

    trait :failed do
      status { :failed }
      error_message { "Invalid phone number" }
    end
    
    trait :pending do 
      status { :pending }
      sent_at { nil }
    end
  end
end 