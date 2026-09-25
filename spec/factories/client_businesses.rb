FactoryBot.define do
  factory :client_business do
    # Associate with existing or newly created records
    association :user, factory: :user, role: :client # Ensure user is a client
    business { ActsAsTenant.current_tenant || association(:business) }
  end
end
