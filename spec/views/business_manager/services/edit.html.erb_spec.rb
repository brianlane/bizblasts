require 'rails_helper'

RSpec.describe "business_manager/services/edit.html.erb", type: :view do
  let(:business) { FactoryBot.create(:business) }
  let(:manager_user) { FactoryBot.create(:user, :manager, business: business) }
  let!(:staff1) { FactoryBot.create(:user, :staff, business: business, first_name: "Staff", last_name: "One") }
  # Create a persisted service record for editing
  let!(:service) { FactoryBot.create(:service, business: business, name: "Existing Service", price: 99.99, duration: 45, description: "Old description") }

  before(:each) do
    # Required for Pundit policies used in the view/form
    allow(view).to receive(:current_user).and_return(manager_user)
    allow(view).to receive(:policy).with(service).and_return(ServicePolicy.new(manager_user, service))
    
    # Assign instance variables expected by the view and form partial
    assign(:service, service)
    assign(:current_business, business)
    
    render
  end

  it "renders the edit service form with existing values" do
    # Check for the form targeting the correct update path
    # Note: Using have_selector with attribute checks is more robust than assuming exact path string
    expect(rendered).to have_selector("form[action='/services/#{service.id}'][method='post']") do |form|
      expect(form).to have_field('_method', type: 'hidden', with: 'patch') # Check for PATCH method
      
      # Check that fields are pre-filled with existing values
      expect(form).to have_field('service[name]', with: service.name)
      expect(form).to have_field('service[price]', with: service.price)
      expect(form).to have_field('service[duration]', with: service.duration)
      expect(form).to have_field('service[description]', with: service.description)
      expect(form).to have_field('service[featured]', type: 'checkbox')
      expect(form).to have_field('service[active]', type: 'checkbox')
      expect(form).to have_field('service[availability_settings]')
      # Check for staff assignment checkboxes
      expect(form).to have_field("service[user_ids][]", id: "user_#{staff1.id}", type: 'checkbox')
      
      expect(form).to have_button('Update Service') # Default submit button text for update
      expect(form).to have_link('Cancel', href: '/services')
    end
  end
end
