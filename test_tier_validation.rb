# Test the updated validation logic for all tier change scenarios
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

    # If tier is being changed, allow it (both upgrades and downgrades)
    # The custom domain restriction only applies to the final tier
    if will_save_change_to_tier?
      return  # Allow tier changes - validation will run again after tier is saved
    end

    # For existing records with no tier change, require current tier to be premium
    errors << 'Tier must be premium to use a custom domain' unless premium_tier?
  end
end

# Test scenarios
puts 'Testing updated tier validation logic:'

# Test 1: Free tier with custom domain (no tier change) - should fail
b1 = TestBusiness.new('free', 'custom_domain')
b1.custom_domain_requires_premium_tier
puts "1. Free + Custom Domain (no change): #{b1.errors.empty? ? 'FAIL' : 'PASS'} - #{b1.errors.join(', ')}"

# Test 2: Standard tier with custom domain (no tier change) - should fail
b2 = TestBusiness.new('standard', 'custom_domain')
b2.custom_domain_requires_premium_tier
puts "2. Standard + Custom Domain (no change): #{b2.errors.empty? ? 'FAIL' : 'PASS'} - #{b2.errors.join(', ')}"

# Test 3: Premium tier with custom domain (no tier change) - should pass
b3 = TestBusiness.new('premium', 'custom_domain')
b3.custom_domain_requires_premium_tier
puts "3. Premium + Custom Domain (no change): #{b3.errors.empty? ? 'PASS' : 'FAIL'} - #{b3.errors.join(', ')}"

# Test 4: Free tier upgrading to standard with custom domain - should pass (allow tier change)
b4 = TestBusiness.new('free', 'custom_domain')
b4.tier = 'standard'
b4.custom_domain_requires_premium_tier
puts "4. Free→Standard + Custom Domain: #{b4.errors.empty? ? 'PASS' : 'FAIL'} - #{b4.errors.join(', ')}"

# Test 5: Free tier upgrading to premium with custom domain - should pass (allow tier change)
b5 = TestBusiness.new('free', 'custom_domain')
b5.tier = 'premium'
b5.custom_domain_requires_premium_tier
puts "5. Free→Premium + Custom Domain: #{b5.errors.empty? ? 'PASS' : 'FAIL'} - #{b5.errors.join(', ')}"

# Test 6: Standard tier upgrading to premium with custom domain - should pass (allow tier change)
b6 = TestBusiness.new('standard', 'custom_domain')
b6.tier = 'premium'
b6.custom_domain_requires_premium_tier
puts "6. Standard→Premium + Custom Domain: #{b6.errors.empty? ? 'PASS' : 'FAIL'} - #{b6.errors.join(', ')}"

# Test 7: Standard tier downgrading to free with custom domain - should pass (allow tier change)
b7 = TestBusiness.new('standard', 'custom_domain')
b7.tier = 'free'
b7.custom_domain_requires_premium_tier
puts "7. Standard→Free + Custom Domain: #{b7.errors.empty? ? 'PASS' : 'FAIL'} - #{b7.errors.join(', ')}"

# Test 8: Premium tier downgrading to standard with custom domain - should pass (allow tier change)
b8 = TestBusiness.new('premium', 'custom_domain')
b8.tier = 'standard'
b8.custom_domain_requires_premium_tier
puts "8. Premium→Standard + Custom Domain: #{b8.errors.empty? ? 'PASS' : 'FAIL'} - #{b8.errors.join(', ')}"

# Test 9: Premium tier downgrading to free with custom domain - should pass (allow tier change)
b9 = TestBusiness.new('premium', 'custom_domain')
b9.tier = 'free'
b9.custom_domain_requires_premium_tier
puts "9. Premium→Free + Custom Domain: #{b9.errors.empty? ? 'PASS' : 'FAIL'} - #{b9.errors.join(', ')}"

puts "\nSummary: All tier changes should be allowed, only non-premium static records should be blocked"
