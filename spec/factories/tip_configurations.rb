FactoryBot.define do
  factory :tip_configuration do
    business
    default_tip_percentages { [15, 18, 20] }
    custom_tip_enabled { true }
    tip_message { "Thank you for your business! Tips are greatly appreciated." }
    
    trait :custom_disabled do
      custom_tip_enabled { false }
    end
    
    trait :high_percentages do
      default_tip_percentages { [20, 25, 30] }
    end
    
    trait :low_percentages do
      default_tip_percentages { [10, 12, 15] }
    end
    
    trait :no_message do
      tip_message { nil }
    end
    
    trait :with_custom_message do
      tip_message { "Your generosity helps our team provide exceptional service!" }
    end
  end
end 