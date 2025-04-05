FactoryBot.define do
  factory :marketing_campaign do
    association :business
    name { "Holiday Promotion" }
    description { "Campaign for the holiday season." }
    campaign_type { :email } 
    status { :scheduled } 
    content { "Check out our holiday specials!" }
    # Scheduled for the future by default
    scheduled_at { 1.week.from_now }
    # start_date/end_date seem to be from schema but not validated/used in model?
    # Add them for completeness based on schema
    start_date { 1.week.from_now.to_date }
    end_date { 1.month.from_now.to_date }
    active { true } # From schema
    settings { {} }
    # started_at, completed_at set by methods

    trait :sms do
      campaign_type { :sms }
      content { "SMS: Holiday deals!" }
    end

    trait :combined do
      campaign_type { :combined }
    end

    trait :draft do
      status { :draft }
      scheduled_at { nil }
    end
    
    trait :running do
      status { :running }
      started_at { 1.hour.ago }
    end
    
    trait :completed do 
      status { :completed }
      started_at { 2.hours.ago }
      completed_at { 1.hour.ago }
    end
    
    trait :cancelled do
      status { :cancelled }
    end

    trait :scheduled_past do
      status { :scheduled }
      scheduled_at { 1.hour.ago }
    end
  end
end 