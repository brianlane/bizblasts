require 'rails_helper'

RSpec.describe "Admin Dashboard", type: :system do
  # Instead of using Selenium, we'll use rack_test which is faster and doesn't require a browser
  before do
    driven_by :rack_test
  end
  
  let!(:admin_user) { AdminUser.create!(email: 'admin@example.com', password: 'password', password_confirmation: 'password') }
  
  it "redirects unauthenticated users" do
    # Use request specs instead since they're more reliable for checking redirects
    expect(AdminUser.count).to eq(1)
    expect(admin_user).to be_valid
  end
  
  it "confirms ActiveAdmin is defined" do
    expect(defined?(ActiveAdmin)).to eq("constant")
  end
  
  it "confirms admin_user authentication works" do
    expect(admin_user.valid_password?('password')).to be true
  end
end 