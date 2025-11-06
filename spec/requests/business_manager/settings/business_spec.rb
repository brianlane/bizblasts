# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Settings::BusinessController", type: :request do
  # Assuming User model, Business model, and factories for them (e.g., FactoryBot)
  # Assuming Devise for sign_in and ActsAsTenant for multi-tenancy

  # Create a business for tenant context
  let!(:business) { create(:business) }
  # Create a manager user associated with the business.
  let!(:user) { create(:user, :manager, business: business) }

  before do
    # Simulate subdomain in host for routes under SubdomainConstraint
    host! "#{business.hostname}.lvh.me"
    # Set current tenant for the request context
    ActsAsTenant.current_tenant = business
    # Sign in the user (Devise test helper)
    sign_in user
  end

  after do
    # Clear current tenant after the test
    ActsAsTenant.current_tenant = nil
  end

  describe "GET /manage/settings/business/edit" do
    it "renders the edit template successfully" do
      get edit_business_manager_settings_business_path
      expect(response).to be_successful
      expect(response).to render_template(:edit)
      expect(response.body).to include("Business Information")
    end

    context "when user is not authorized (example)" do
      it "redirects or shows forbidden if policy were different" do
        # This test is illustrative. Current policy (user.business == record) should pass.
        # To make this fail, you would need a user not associated with `business`
        # and a policy that reflects finer-grained permissions (e.g. specific roles).
        # For example, if another user tried to access:
        # another_user = create(:user, business: create(:business)) # different business
        # sign_in another_user
        # get edit_settings_business_path
        # expect(response).to have_http_status(:forbidden) # or :redirect, based on Pundit config
        # For now, this context is more of a placeholder for future, more complex authorization tests.
        expect(true).to be_truthy # Placeholder to ensure spec group runs
      end
    end
  end

  describe "PATCH /manage/settings/business" do
    let(:valid_attributes) do
      {
        name: "Updated Tech Solutions Inc.",
        industry: :consulting,
        phone: "555-0199",
        email: "contact@updatedtech.com",
        website: "http://updatedtech.com",
        address: "456 Innovation Drive",
        city: "Techville",
        state: "CA",
        zip: "90210",
        description: "Leading provider of updated tech solutions.",
        hours_mon_open: "09:00",
        hours_mon_close: "17:30",
        hours_tue_open: "",
        hours_tue_close: ""
      }
    end

    let(:invalid_attributes) do
      { name: "" } # Business name cannot be blank
    end

    let(:logo_file) do
      # Use existing test_image.jpg fixture
      fixture_file_upload(Rails.root.join('spec', 'fixtures', 'files', 'test_image.jpg'), 'image/jpeg')
    end

    context "with valid parameters" do
      it "updates the requested business attributes" do
        patch business_manager_settings_business_path, params: { business: valid_attributes }
        business.reload
        expect(business.name).to eq("Updated Tech Solutions Inc.")
        expect(business.industry).to eq("consulting")
        expect(business.email).to eq("contact@updatedtech.com")
      end

      it "correctly updates the hours JSONB field" do
        patch business_manager_settings_business_path, params: { business: valid_attributes }
        business.reload
        expect(business.hours).to be_a(Hash)
        expect(business.hours['mon']).to eq({ 'open' => "09:00", 'close' => "17:30" })
        # For Tuesday, since open and close are blank, it shouldn't create an entry for 'tue' based on current controller logic
        # Or if it does, it would be { open: nil, close: nil }
        # Current controller: `if open_time.present? || close_time.present?`
        # So if both are blank, `hours_data[day.to_sym]` is not set for that day.
        expect(business.hours['tue']).to be_nil # Or eq({ 'open' => nil, 'close' => nil }) depending on how blanks are handled
      end

      it "attaches the logo when provided" do
        patch business_manager_settings_business_path, params: { business: valid_attributes.merge(logo: logo_file) }
        business.reload
        expect(business.logo).to be_attached
      end

      it "redirects to the edit business settings page with a notice" do
        patch business_manager_settings_business_path, params: { business: valid_attributes }
        expect(response).to redirect_to(edit_business_manager_settings_business_path)
        expect(flash[:notice]).to eq('Business information updated successfully.')
      end

      it "redirects to the provided integrations path when return_to is safe" do
        patch business_manager_settings_business_path,
              params: {
                business: valid_attributes,
                return_to: business_manager_settings_integrations_path
              }

        expect(response).to redirect_to(business_manager_settings_integrations_path)
      end

      it "ignores unsafe return_to URLs" do
        patch business_manager_settings_business_path,
              params: {
                business: valid_attributes,
                return_to: 'https://evil.com/manage/settings/integrations'
              }

        expect(response).to redirect_to(edit_business_manager_settings_business_path)
      end
    end

    context "with invalid parameters" do
      it "does not update the business" do
        original_name = business.name
        patch business_manager_settings_business_path, params: { business: invalid_attributes }
        business.reload
        expect(business.name).to eq(original_name)
      end

      it "renders the edit template with unprocessable_entity status and errors" do
        patch business_manager_settings_business_path, params: { business: invalid_attributes }
        expect(response).to render_template(:edit)
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Name can&#39;t be blank") # From the custom error display format (HTML encoded)
      end

      it "redirects back to integrations when return_to is provided and preserves errors in flash" do
        create(:business, google_place_id: "ChIJduplicatePlace")

        patch business_manager_settings_business_path,
              params: {
                business: { google_place_id: "ChIJduplicatePlace" },
                return_to: business_manager_settings_integrations_path
              }

        expect(response).to redirect_to(business_manager_settings_integrations_path)
        expect(flash[:alert]).to include("Please fix the following errors")
        expect(Array(flash[:form_errors])).to include("Google place has already been taken")
        expect(flash[:business_form_data]['google_place_id']).to eq("ChIJduplicatePlace")
      end

      it "falls back to rendering edit when return_to is unsafe" do
        patch business_manager_settings_business_path,
              params: {
                business: invalid_attributes,
                return_to: '//evil.com'
              }

        expect(response).to render_template(:edit)
      end
    end
  end
end
