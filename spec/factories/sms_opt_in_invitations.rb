FactoryBot.define do
  factory :sms_opt_in_invitation do
    association :business
    association :tenant_customer

    phone_number { tenant_customer&.phone || '+15551234567' }
    context { 'booking_confirmation' }
    sent_at { Time.current }
    responded_at { nil }
    response { nil }
    successful_opt_in { false }

    trait :responded do
      responded_at { Time.current }
      response { 'YES' }
      successful_opt_in { true }
    end

    trait :declined do
      responded_at { Time.current }
      response { 'NO' }
      successful_opt_in { false }
    end

    trait :old do
      sent_at { 31.days.ago }
    end

    trait :recent do
      sent_at { 1.day.ago }
    end

    # Callback to ensure phone number matches customer if present
    after(:build) do |invitation|
      if invitation.tenant_customer&.phone
        invitation.phone_number = invitation.tenant_customer.phone
      end
    end
  end
end
