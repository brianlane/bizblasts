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
    
    # Create admin user if it doesn't exist
    admin_email = ENV['ADMIN_EMAIL'] || 'admin@example.com'
    password = ENV['ADMIN_PASSWORD'] || 'password123'
    
    @admin_user = AdminUser.find_by(email: admin_email)
    unless @admin_user
      @admin_user = AdminUser.create!(
        email: admin_email,
        password: password,
        password_confirmation: password
      )
    end
    
    # Sign in as admin user via warden
    post admin_user_session_path, params: {
      admin_user: {
        email: admin_email,
        password: password
      }
    }
  end
  
  # Clean up after each test that uses ActiveAdmin
  config.after(:each, type: :request, admin: true) do
    delete destroy_admin_user_session_path
  end
end 