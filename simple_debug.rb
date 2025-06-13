require 'factory_bot_rails'
FactoryBot.find_definitions

# Create test data
business = FactoryBot.create(:business, hostname: 'test', referral_program_enabled: true)
user = FactoryBot.create(:user, :client)
ActsAsTenant.current_tenant = business

# Create referral program
program = business.create_referral_program!(
  active: true,
  referrer_reward_type: 'points',
  referrer_reward_value: 100,
  referral_code_discount_amount: 10.0,
  min_purchase_amount: 0.0
)

puts "Business: #{business.name}"
puts "User: #{user.full_name}"
puts "Program active: #{program.active}"

# Test creating referral
puts "Creating referral..."
referral = Referral.new(business: business, referrer: user, status: 'pending')
puts "Before save - code: #{referral.referral_code}"
referral.save!
puts "After save - code: #{referral.referral_code}, id: #{referral.id}" 