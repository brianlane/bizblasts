require 'rails_helper'

RSpec.describe "business_manager/services/new.html.erb", type: :view do
  let(:business) { FactoryBot.create(:business) }
  let(:manager_user) { FactoryBot.create(:user, :manager, business: business) }
  let!(:staff1) { FactoryBot.create(:user, :staff, business: business, first_name: "Staff", last_name: "One") }
  let(:service) { Service.new(business: business) }

  before(:each) do
    # Required for Pundit policies used in the view/form
    allow(view).to receive(:current_user).and_return(manager_user)
    allow(view).to receive(:policy).with(service).and_return(ServicePolicy.new(manager_user, service))
    
    # Assign instance variables expected by the view and form partial
    assign(:service, service)
    assign(:current_business, business)
    
    render
  end

  it "renders the new service form" do
    # Check for the form targeting the correct path (using default Rails convention for new)
    expect(rendered).to have_selector("form[action='/services'][method='post']") do |form|
      expect(form).to have_field('service[name]')
      expect(form).to have_field('service[price]')
      expect(form).to have_field('service[duration]')
      expect(form).to have_field('service[description]')
      expect(form).to have_field('service[featured]', type: 'checkbox')
      expect(form).to have_field('service[active]', type: 'checkbox')
      expect(form).to have_field('service[availability_settings]')
      # Check for staff assignment checkboxes
      expect(form).to have_field("service[user_ids][]", id: "user_#{staff1.id}", type: 'checkbox')
      expect(form).to have_button('Create Service') # Default submit button text
      expect(form).to have_link('Cancel', href: '/services')
    end
  end
end
