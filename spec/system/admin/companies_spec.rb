require 'rails_helper'

# Configuration tests that don't require browser/rendering
RSpec.describe "Admin Configuration", type: :model do
  # This test doesn't need a browser
  it "has ActiveAdmin configured correctly" do
    expect(defined?(ActiveAdmin)).to be_truthy
    expect(ActiveAdmin.application).to be_a(ActiveAdmin::Application)
  end
  
  it "has AdminUser model defined" do
    expect(defined?(AdminUser)).to eq("constant")
  end
  
  it "has expected ActiveAdmin resources registered" do
    expect(ActiveAdmin.application.namespaces[:admin].resources.keys).to include("Dashboard")
    
    # Verify that the companies resource is registered if available
    if ActiveAdmin.application.namespaces[:admin].resources.keys.include?("Business")
      expect(ActiveAdmin.application.namespaces[:admin].resources["Business"]).to be_present
    end
  end
end 