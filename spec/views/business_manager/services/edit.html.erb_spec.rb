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
    
    # Ensure staff member exists for the business for the form checkboxes
    create(:staff_member, business: business, name: "Staff One") # Using a different name/record than staff1 user
    
    render
  end

  it "renders the edit service form with existing values" do
    # Check for the form targeting the correct update path with business_manager namespace
    expect(rendered).to have_selector("form[action='/manage/services/#{service.id}'][method='post']") do |form|
      expect(form).to have_field('_method', type: 'hidden', with: 'patch') # Check for PATCH method
      
      # Check that fields are pre-filled with existing values
      expect(form).to have_field('service[name]', with: service.name)
      expect(form).to have_field('service[price]', with: service.price)
      expect(form).to have_field('service[duration]', with: service.duration)
      expect(form).to have_field('service[description]', with: service.description)
      expect(form).to have_field('service[featured]', type: 'checkbox')
      expect(form).to have_field('service[active]', type: 'checkbox')
      expect(form).to have_field('service[staff_member_ids][]', type: 'checkbox')
      
      expect(form).to have_button('Update Service') # Corrected submit button text for edit record
    end
  end
end
