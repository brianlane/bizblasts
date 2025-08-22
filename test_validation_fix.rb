# Test the corrected validation logic
class TestBusiness
  attr_accessor :tier, :host_type, :errors

  def initialize(tier, host_type)
    @tier = tier
    @host_type = host_type
    @errors = []
    @tier_before_last_save = tier  # Simulate initial state
  end

  def host_type_custom_domain?
    host_type == 'custom_domain'
  end

  def premium_tier?
    tier == 'premium'
  end

  def premium_tier_was?
    tier_before_last_save == 'premium'
  end

  def will_save_change_to_tier?
    tier != tier_before_last_save
  end

  def tier_before_last_save
    @tier_before_last_save
  end

  def tier=(new_tier)
    @tier_before_last_save = @tier if @tier  # Store previous tier
    @tier = new_tier
  end

  def custom_domain_requires_premium_tier
    return unless host_type_custom_domain?

    # Check the tier that will be saved (new value if changing, current value if not)
    final_tier = tier_before_last_save || tier
    if will_save_change_to_tier? && tier
      final_tier = tier  # Use the new tier value if it's being changed
    end

    # Allow downgrades from premium (preserve existing custom domains)
    if will_save_change_to_tier? && premium_tier_was? && final_tier != 'premium'
      return
    end

    # Require premium tier for custom domains
    unless final_tier == 'premium'
      errors << 'Tier must be premium to use a custom domain'
    end
  end
end

# Test scenarios
puts 'Testing corrected validation logic:'

# Test 1: Static records (no tier change)
puts "\n1. STATIC RECORDS (no tier change):"
b1 = TestBusiness.new('free', 'custom_domain')
b1.custom_domain_requires_premium_tier
puts "   Free + Custom Domain: #{b1.errors.empty? ? 'FAIL (should be blocked)' : 'PASS (correctly blocked)'}"

b2 = TestBusiness.new('standard', 'custom_domain')
b2.custom_domain_requires_premium_tier
puts "   Standard + Custom Domain: #{b2.errors.empty? ? 'FAIL (should be blocked)' : 'PASS (correctly blocked)'}"

b3 = TestBusiness.new('premium', 'custom_domain')
b3.custom_domain_requires_premium_tier
puts "   Premium + Custom Domain: #{b3.errors.empty? ? 'PASS (correctly allowed)' : 'FAIL (should be allowed)'}"

# Test 2: Upgrades to premium
puts "\n2. UPGRADES TO PREMIUM:"
b4 = TestBusiness.new('free', 'custom_domain')
b4.tier = 'premium'
b4.custom_domain_requires_premium_tier
puts "   Free→Premium + Custom Domain: #{b4.errors.empty? ? 'PASS (correctly allowed)' : 'FAIL (should be allowed)'}"

b5 = TestBusiness.new('standard', 'custom_domain')
b5.tier = 'premium'
b5.custom_domain_requires_premium_tier
puts "   Standard→Premium + Custom Domain: #{b5.errors.empty? ? 'PASS (correctly allowed)' : 'FAIL (should be allowed)'}"

# Test 3: Changes to non-premium
puts "\n3. CHANGES TO NON-PREMIUM:"
b6 = TestBusiness.new('free', 'custom_domain')
b6.tier = 'standard'
b6.custom_domain_requires_premium_tier
puts "   Free→Standard + Custom Domain: #{b6.errors.empty? ? 'FAIL (should be blocked)' : 'PASS (correctly blocked)'}"

b7 = TestBusiness.new('premium', 'custom_domain')
b7.tier = 'free'
b7.custom_domain_requires_premium_tier
puts "   Premium→Free + Custom Domain: #{b7.errors.empty? ? 'PASS (downgrade allowed)' : 'FAIL (downgrade should be allowed)'}"

b8 = TestBusiness.new('premium', 'custom_domain')
b8.tier = 'standard'
b8.custom_domain_requires_premium_tier
puts "   Premium→Standard + Custom Domain: #{b8.errors.empty? ? 'PASS (downgrade allowed)' : 'FAIL (downgrade should be allowed)'}"

b9 = TestBusiness.new('standard', 'custom_domain')
b9.tier = 'free'
b9.custom_domain_requires_premium_tier
puts "   Standard→Free + Custom Domain: #{b9.errors.empty? ? 'FAIL (should be blocked)' : 'PASS (correctly blocked)'}"

puts "\nSUMMARY:"
puts "- Only premium tier can use custom domains (static or target tier)"
puts "- Downgrades from premium preserve custom domains"
puts "- All other non-premium combinations are blocked"
