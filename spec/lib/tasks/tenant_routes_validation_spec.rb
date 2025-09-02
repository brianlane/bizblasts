require 'rails_helper'
require 'rake'

RSpec.describe 'tenant:validate_routes', type: :task do
  before(:all) do
    Rake.application.rake_require 'tasks/tenant_routes_validation'
    Rake::Task.define_task(:environment)
  end

  let(:task) { Rake::Task['tenant:validate_routes'] }
  let!(:subdomain_business) do
    create(:business, 
           name: 'Route Test Subdomain Business',
           subdomain: 'routetest',
           host_type: 'subdomain',
           status: 'active')
  end
  
  let!(:custom_domain_business) do
    create(:business,
           name: 'Route Test Custom Domain Business', 
           subdomain: 'customtest',
           hostname: 'routetest.example.com',
           host_type: 'custom_domain',
           status: 'cname_active')
  end

  before do
    task.reenable
  end

  describe 'route validation' do
    it 'validates routes for both subdomain and custom domain businesses' do
      # Capture the output
      output = capture_stdout { task.invoke }
      
      # Should test both domain types
      expect(output).to include('Testing subdomain host: routetest.bizblasts.com')
      expect(output).to include('Testing custom_domain host: routetest.example.com')
      
      # Should test core routes
      expect(output).to include('Homepage → public/pages#show')
      expect(output).to include('Services page → public/pages#show')
      expect(output).to include('Cart → public/carts#show')
      expect(output).to include('Orders index → public/orders#index')
      expect(output).to include('New payment → public/payments#new')
      
      # Should show success for both domain types
      expect(output).to include('✅')
      expect(output).to include('public/')
    end

    it 'tests constraint logic for different host types' do
      output = capture_stdout { task.invoke }
      
      # Should test constraint matching
      expect(output).to include('Testing Constraint Logic')
      expect(output).to include('routetest.bizblasts.com (subdomain) → MATCH')
      expect(output).to include('routetest.example.com (custom_domain) → MATCH')
      expect(output).to include('bizblasts.com (platform) → NO MATCH')
      expect(output).to include('www.bizblasts.com (platform) → NO MATCH')
      expect(output).to include('nonexistent.com (unknown) → NO MATCH')
    end

    it 'reports validation success when all routes work' do
      output = capture_stdout { task.invoke }
      
      expect(output).to include('VALIDATION PASSED - All tenant routes work correctly!')
    end
  end

  describe 'route structure display' do
    let(:show_task) { Rake::Task['tenant:show_routes'] }
    
    before do
      show_task.reenable
    end

    it 'displays current tenant route structure' do
      output = capture_stdout { show_task.invoke }
      
      expect(output).to include('Current Tenant Route Structure')
      expect(output).to include('TenantPublicConstraint Routes:')
      expect(output).to include('Platform Routes:')
      expect(output).to include('Constraint Files:')
      expect(output).to include('Documentation:')
      expect(output).to include('docs/TENANT_ROUTING_GUIDE.md')
    end
  end

  private

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    begin
      yield
      $stdout.string
    ensure
      $stdout = original_stdout
    end
  end
end

RSpec.describe 'Tenant Route Integration', type: :routing do
  let!(:subdomain_business) do
    create(:business, 
           subdomain: 'integrationtest',
           host_type: 'subdomain',
           status: 'active')
  end
  
  let!(:custom_domain_business) do
    create(:business,
           subdomain: 'customintegration',
           hostname: 'integration.example.com',
           host_type: 'custom_domain',
           status: 'cname_active')
  end

  describe 'constraint validation' do
    def create_mock_request(host)
      Class.new do
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
      end.new(host)
    end

    it 'TenantPublicConstraint matches subdomain requests' do
      request = create_mock_request('integrationtest.bizblasts.com')
      expect(TenantPublicConstraint.matches?(request)).to be true
    end

    it 'TenantPublicConstraint matches custom domain requests' do
      request = create_mock_request('integration.example.com')
      expect(TenantPublicConstraint.matches?(request)).to be true
    end

    it 'TenantPublicConstraint rejects platform requests' do
      platform_hosts = ['bizblasts.com', 'www.bizblasts.com', 'bizblasts.onrender.com']
      
      platform_hosts.each do |host|
        request = create_mock_request(host)
        expect(TenantPublicConstraint.matches?(request)).to be false,
          "Expected TenantPublicConstraint to reject #{host}"
      end
    end
  end

  describe 'route existence validation' do
    it 'verifies all expected tenant routes exist' do
      expected_routes = [
        { name: 'tenant_root', controller: 'public/pages' },
        { name: 'tenant_services_page', controller: 'public/pages' },
        { name: 'tenant_about_page', controller: 'public/pages' },
        { name: 'new_tenant_booking', controller: 'public/booking' },
        { name: 'cart', controller: 'public/carts' },
        { name: 'payments', controller: 'public/payments' },
        { name: 'new_payment', controller: 'public/payments' },
        { name: 'tenant_calendar', controller: 'public/tenant_calendar' },
        { name: 'products', controller: 'public/products' }
      ]
      
      all_routes = Rails.application.routes.routes.map do |route|
        {
          name: route.name,
          controller: route.defaults[:controller],
          action: route.defaults[:action]
        }
      end
      
      expected_routes.each do |expected_route|
        found_route = all_routes.find { |r| r[:name] == expected_route[:name] }
        
        expect(found_route).to be_present, 
          "Route #{expected_route[:name]} not found"
        expect(found_route[:controller]).to eq(expected_route[:controller]),
          "Route #{expected_route[:name]} points to #{found_route[:controller]} instead of #{expected_route[:controller]}"
      end
    end
  end

  describe 'platform domain exclusion' do
    it 'platform domains route to home controller' do
      platform_hosts = ['bizblasts.com', 'www.bizblasts.com']
      
      platform_hosts.each do |host|
        recognized = Rails.application.routes.recognize_path('/', method: :get, host: host)
        expect(recognized[:controller]).to eq('home'), 
          "Expected #{host} to route to home controller, got #{recognized[:controller]}"
      end
    end
  end
end
