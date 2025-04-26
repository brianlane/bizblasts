require 'rails_helper'

RSpec.describe "business_manager/services/index.html.erb", type: :view do
  include Pundit::Authorization
  
  let(:business) { FactoryBot.create(:business) }
  let(:manager_user) { FactoryBot.create(:user, :manager, business: business) }
  let!(:service1) { FactoryBot.create(:service, business: business, name: "Service One") }
  let!(:service2) { FactoryBot.create(:service, business: business, name: "Service Two") }

  before(:each) do
    # Set current user for Pundit
    allow(view).to receive(:current_user).and_return(manager_user)
    allow(view).to receive(:policy).with(Service).and_return(ServicePolicy.new(manager_user, Service))
    allow(view).to receive(:policy).with(service1).and_return(ServicePolicy.new(manager_user, service1))
    allow(view).to receive(:policy).with(service2).and_return(ServicePolicy.new(manager_user, service2))
    
    # Simulate paginated collection
    services = Kaminari.paginate_array([service1, service2]).page(1)
    assign(:services, services)
    assign(:current_business, business)
    render
  end

  it "renders a list of services with appropriate action links/buttons" do
    # render # Removed extra render call
    
    # Check for 'New Service' link
    expect(rendered).to have_link('New Service', href: new_business_manager_service_path)
    
    # Check table headers
    expect(rendered).to have_selector('th', text: 'Name')
    expect(rendered).to have_selector('th', text: 'Price')
    expect(rendered).to have_selector('th', text: 'Duration')
    # expect(rendered).to have_selector('th', text: 'Actions') # Removed as Actions header might be implicit
    
    # Check content for each service and action links
    expect(rendered).to have_selector('tbody tr', count: 2) # Ensure only 2 service rows
    expect(rendered).to include("Service One")
    expect(rendered).to include("Service Two")
    expect(rendered).to have_link('Edit', href: edit_business_manager_service_path(service1))
    expect(rendered).to have_link('Edit', href: edit_business_manager_service_path(service2))
    # Check for delete links by class within table rows
    expect(rendered).to have_link('Delete', class: 'delete-link', count: 2)
  end
end
