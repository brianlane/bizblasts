# Test the validation logic
class TestBusiness
  attr_accessor :tier, :host_type, :errors

  def initialize(tier, host_type)
    @tier = tier
    @host_type = host_type
    @errors = []
  end

  def host_type_custom_domain?
    host_type == 'custom_domain'
  end

  def premium_tier?
    tier == 'premium'
  end

  def premium_tier_was?
    # Simulate different scenarios
    false # For simplicity in this test
  end

  def will_save_change_to_tier?
    # Simulate different scenarios
    false # For simplicity in this test
  end

  def custom_domain_requires_premium_tier
    return unless host_type_custom_domain?

    # Permit downgrade flow (tier is being changed from premium to non-premium)
    if will_save_change_to_tier? && premium_tier_was? && !premium_tier?
      return
    end

    # Otherwise require current tier to be premium
    errors << 'Tier must be premium to use a custom domain' unless premium_tier?
  end
end

# Test cases
puts 'Testing validation logic:'

# Test 1: Premium tier with custom domain (should pass)
b1 = TestBusiness.new('premium', 'custom_domain')
b1.custom_domain_requires_premium_tier
puts "1. Premium + Custom Domain: #{b1.errors.empty? ? 'PASS' : 'FAIL'} - #{b1.errors.join(', ')}"

# Test 2: Standard tier with custom domain (should fail)
b2 = TestBusiness.new('standard', 'custom_domain')
b2.custom_domain_requires_premium_tier
puts "2. Standard + Custom Domain: #{b2.errors.empty? ? 'FAIL' : 'PASS'} - #{b2.errors.join(', ')}"

# Test 3: Free tier with custom domain (should fail)
b3 = TestBusiness.new('free', 'custom_domain')
b3.custom_domain_requires_premium_tier
puts "3. Free + Custom Domain: #{b3.errors.empty? ? 'FAIL' : 'PASS'} - #{b3.errors.join(', ')}"

# Test 4: Standard tier with subdomain (should pass)
b4 = TestBusiness.new('standard', 'subdomain')
b4.custom_domain_requires_premium_tier
puts "4. Standard + Subdomain: #{b4.errors.empty? ? 'PASS' : 'FAIL'} - #{b4.errors.join(', ')}"
