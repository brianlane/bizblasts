RSpec.configure do |config|
  # Mock asset pipeline helpers for ActiveAdmin in tests
  config.before(:each, type: :request, admin: true) do
    # Allow the stylesheet_link_tag to work without actually requiring assets
    allow_any_instance_of(ActionView::Base).to receive(:stylesheet_link_tag) do |*args|
      # Just return a dummy script tag instead of trying to load real assets
      "<link rel=\"stylesheet\" href=\"/dummy.css\" />"
    end
    
    # Similar for javascript_include_tag
    allow_any_instance_of(ActionView::Base).to receive(:javascript_include_tag) do |*args|
      "<script src=\"/dummy.js\"></script>"
    end
    
    # No need to mock Ransack here, we'll handle it in the business model
    
    # Use FactoryBot with worker number to ensure unique email in parallel
    worker_num = ENV['TEST_ENV_NUMBER']
    @admin_user = create(:admin_user, email: "admin-#{worker_num || '0'}-#{SecureRandom.hex(4)}@example.com") # Add random hex for extra safety
    
    # Sign in as admin user via warden
    post admin_user_session_path, params: {
      admin_user: {
        email: @admin_user.email,
        password: @admin_user.password # Use the factory generated password
      }
    }
  end
  
  # Clean up after each test that uses ActiveAdmin
  config.after(:each, type: :request, admin: true) do
    delete destroy_admin_user_session_path
  end
end 