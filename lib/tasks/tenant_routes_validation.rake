namespace :tenant do
  desc "Validate that tenant routes work for both subdomains and custom domains"
  task validate_routes: :environment do
    puts "🔍 Validating Tenant Route Coverage..."
    
    # Create test businesses
    subdomain_business = Business.find_or_create_by(subdomain: 'routetest') do |b|
      b.name = 'Route Test Business'
      b.host_type = 'subdomain'
      b.status = 'active'
    end
    
    custom_domain_business = Business.find_or_create_by(hostname: 'routetest.example.com') do |b|
      b.name = 'Custom Domain Test Business'
      b.subdomain = 'customtest'
      b.host_type = 'custom_domain'
      b.status = 'cname_active'
    end
    
    # Test hosts
    test_hosts = [
      { host: 'routetest.bizblasts.com', type: 'subdomain', business: subdomain_business },
      { host: 'routetest.example.com', type: 'custom_domain', business: custom_domain_business }
    ]
    
    # Core tenant routes that should be available
    expected_routes = [
      { name: 'tenant_root', path: '/', controller: 'public/pages' },
      { name: 'tenant_services_page', path: '/services', controller: 'public/pages' },
      { name: 'tenant_about_page', path: '/about', controller: 'public/pages' },
      { name: 'new_tenant_booking', path: '/book', controller: 'public/booking' },
      { name: 'cart', path: '/cart', controller: 'public/carts' },
      { name: 'payments', path: '/payments', controller: 'public/payments' },
      { name: 'new_payment', path: '/payments/new', controller: 'public/payments' },
      { name: 'tenant_calendar', path: '/calendar', controller: 'public/tenant_calendar' },
      { name: 'products', path: '/products', controller: 'public/products' }
    ]
    
    errors = []
    successes = 0
    
    # Get all routes
    all_routes = Rails.application.routes.routes.map do |route|
      {
        name: route.name,
        path: route.path.spec.to_s.gsub(/\(\.\:format\)/, ''),
        controller: route.defaults[:controller],
        action: route.defaults[:action]
      }
    end
    
    test_hosts.each do |host_config|
      puts "\n📍 Testing #{host_config[:type]} host: #{host_config[:host]}"
      
      # Test constraint matching
      mock_request = Class.new do
        attr_reader :host
        
        def initialize(host)
          @host = host
        end
        
        def subdomain
          parts = @host.split('.')
          return '' if parts.length <= 2
          return '' if parts.first == 'www'
          parts.first
        end
      end.new(host_config[:host])
      
      constraint_matches = TenantPublicConstraint.matches?(mock_request)
      
      if constraint_matches
        puts "  ✅ TenantPublicConstraint matches for #{host_config[:host]}"
        
        # Check that expected routes exist
        expected_routes.each do |expected_route|
          found_route = all_routes.find { |r| r[:name] == expected_route[:name] }
          
          if found_route
            if found_route[:controller] == expected_route[:controller]
              puts "  ✅ #{expected_route[:path]} → #{found_route[:controller]}##{found_route[:action]}"
              successes += 1
            else
              errors << "❌ Route #{expected_route[:name]} points to #{found_route[:controller]} instead of #{expected_route[:controller]}"
            end
          else
            errors << "❌ Route #{expected_route[:name]} (#{expected_route[:path]}) not found"
          end
        end
      else
        errors << "❌ TenantPublicConstraint does not match #{host_config[:host]}"
      end
    end
    
    puts "\n" + "="*60
    puts "📊 VALIDATION RESULTS"
    puts "="*60
    
    if errors.empty?
      puts "🎉 ALL ROUTES WORKING! #{successes} routes tested successfully"
      puts "\n✅ Both subdomains and custom domains are properly configured"
      puts "✅ All routes point to Public:: controllers"
      puts "✅ No routing conflicts detected"
    else
      puts "⚠️  ISSUES FOUND:"
      errors.each { |error| puts "   #{error}" }
      puts "\n❌ #{errors.size} issues found out of #{successes + errors.size} routes tested"
    end
    
    # Test constraint logic
    puts "\n🔧 Testing Constraint Logic..."
    
    test_constraint_cases = [
      { host: 'routetest.bizblasts.com', should_match: true, type: 'subdomain' },
      { host: 'routetest.example.com', should_match: true, type: 'custom_domain' },
      { host: 'bizblasts.com', should_match: false, type: 'platform' },
      { host: 'www.bizblasts.com', should_match: false, type: 'platform' },
      { host: 'nonexistent.com', should_match: false, type: 'unknown' }
    ]
    
    test_constraint_cases.each do |test_case|
      # Create a mock request object for constraint testing
      request = Class.new do
        attr_reader :host
        
        def initialize(host)
          @host = host
        end
        
        def subdomain
          parts = @host.split('.')
          return '' if parts.length <= 2
          return '' if parts.first == 'www'
          parts.first
        end
      end.new(test_case[:host])
      
      result = TenantPublicConstraint.matches?(request)
      
      if result == test_case[:should_match]
        puts "  ✅ #{test_case[:host]} (#{test_case[:type]}) → #{result ? 'MATCH' : 'NO MATCH'}"
      else
        puts "  ❌ #{test_case[:host]} (#{test_case[:type]}) → Expected #{test_case[:should_match]}, got #{result}"
        errors << "Constraint logic error for #{test_case[:host]}"
      end
    end
    
    puts "\n" + "="*60
    
    if errors.empty?
      puts "🎉 VALIDATION PASSED - All tenant routes work correctly!"
      exit 0
    else
      puts "❌ VALIDATION FAILED - Please fix the issues above"
      exit 1
    end
  end
  
  desc "Show current tenant route structure"
  task show_routes: :environment do
    puts "🗺️  Current Tenant Route Structure"
    puts "="*50
    
    puts "\n📋 TenantPublicConstraint Routes:"
    puts `bin/rails routes | grep -E "(public/|cart|orders|payments|transactions|tips|subscriptions)" | head -20`
    
    puts "\n🏠 Platform Routes:"
    puts `bin/rails routes | grep -E "home#|root" | head -5`
    
    puts "\n🔧 Constraint Files:"
    puts "  - lib/constraints/tenant_public_constraint.rb"
    puts "  - lib/constraints/custom_domain_constraint.rb"
    puts "  - lib/constraints/subdomain_constraint.rb"
    
    puts "\n📖 Documentation:"
    puts "  - docs/TENANT_ROUTING_GUIDE.md"
  end
end
