require 'rails_helper'

RSpec.describe "Admin::Services", type: :request do
  let(:admin_user) { create(:admin_user) } # Assuming you have an :admin_user factory
  let(:business) { create(:business) }     # Assuming you have a :business factory

  before do
    sign_in admin_user # Assuming Devise or similar helper
  end

  describe "GET /admin/services" do
    let!(:service_with_business_and_price) { create(:service, business: business, price: 100.00) }

    it "displays services correctly" do
      get admin_services_path

      expect(response).to have_http_status(:ok)

      # Check for service with business and price
      expect(response.body).to include(service_with_business_and_price.name)
      expect(response.body).to include(admin_business_path(business.id)) # Check link to business
      expect(response.body).to include("$100.00") # Check formatted price
    end

    # Helper to mimic ActiveAdmin's status_tag for easier assertion
    # You might need to adjust this based on your actual status_tag implementation
    # or make the spec less reliant on exact HTML structure.
    def status_tag(text, class_name = 'ok')
      %(<span class="status_tag #{class_name}">#{text}</span>)
    end
  end

  # TODO: Add tests for create/update/delete actions if permit_params is enabled in app/admin/services.rb
  # TODO: Add tests for filters if they exist.
  # TODO: Add test case for service with a business that exists but lacks name/id (if possible state)
end 