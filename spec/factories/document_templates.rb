FactoryBot.define do
  factory :document_template do
    business
    name { "Default Template" }
    document_type { 'estimate' }
    body { "<p>Standard terms</p>" }
    active { true }
  end
end
