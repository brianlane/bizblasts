require 'rails_helper'

RSpec.describe "BusinessManager::Settings::Locations", type: :request do
  let(:business) { create(:business, :premium_tier) }
  let(:business_manager_user) { create(:user, :manager, business: business) }
  let!(:location) { create(:location, business: business) }

  before do
    host! "#{business.hostname}.lvh.me"
    ActsAsTenant.current_tenant = business
    sign_in business_manager_user
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe "GET /index" do
    it "renders a successful response" do
      get business_manager_settings_locations_path
      expect(response).to be_successful
    end

    it "displays locations" do
      get business_manager_settings_locations_path
      expect(response.body).to include(location.name)
    end

    it "auto-creates a default location if none exists" do
      Location.delete_all
      expect {
        get business_manager_settings_locations_path
      }.to change(Location, :count).by(1)
      expect(Location.last.name).to eq("Main Location")
    end
  end

  describe "GET /new" do
    it "renders a successful response" do
      get new_business_manager_settings_location_path
      expect(response).to be_successful
    end
  end

  describe "POST /create" do
    context "with valid parameters" do
      let(:valid_attributes) do
        attributes_for(:location, business_id: business.id)
      end

      it "creates a new Location" do
        expect do
          post business_manager_settings_locations_path, params: { location: valid_attributes }
        end.to change(Location, :count).by(1)
      end

      it "redirects to the index" do
        post business_manager_settings_locations_path, params: { location: valid_attributes }
        expect(response).to redirect_to(business_manager_settings_locations_path)
      end
    end

    context "with invalid parameters" do
      let(:invalid_attributes) do
        attributes_for(:location, name: "", business_id: business.id)
      end

      it "does not create a new Location" do
        expect do
          post business_manager_settings_locations_path, params: { location: invalid_attributes }
        end.to change(Location, :count).by(0)
      end

      it "renders a unprocessable_content response" do
        post business_manager_settings_locations_path, params: { location: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "GET /edit" do
    it "renders a successful response" do
      get edit_business_manager_settings_location_path(location)
      expect(response).to be_successful
    end
  end

  describe "PATCH /update" do
    context "with valid parameters" do
      let(:new_attributes) { { name: "Updated Location Name" } }

      it "updates the requested location" do
        patch business_manager_settings_location_path(location), params: { location: new_attributes }
        location.reload
        expect(location.name).to eq("Updated Location Name")
      end

      it "redirects to the index" do
        patch business_manager_settings_location_path(location), params: { location: new_attributes }
        expect(response).to redirect_to(business_manager_settings_locations_path)
      end

      it "syncs to business if sync param is set and location is default" do
        allow_any_instance_of(Business).to receive(:default_location).and_return(location)
        patch business_manager_settings_location_path(location), params: { location: new_attributes, sync_to_business: '1' }
        expect(response.body).to include('synced with business information').or include('successfully updated')
      end
    end

    context "with invalid parameters" do
      let(:invalid_attributes) { { name: "" } }

      it "renders a unprocessable_content response" do
        patch business_manager_settings_location_path(location), params: { location: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "with invalid hours JSON" do
      let(:invalid_hours) { { hours: '{invalid_json}' } }
      it "logs error and does not update location" do
        expect(Rails.logger).to receive(:error).at_least(:once)
        patch business_manager_settings_location_path(location), params: { location: invalid_hours }
        expect(response).to render_template(:edit)
      end
    end

    context "with missing required fields" do
      it "does not update location if address is blank" do
        patch business_manager_settings_location_path(location), params: { location: { address: "" } }
        expect(response).to have_http_status(:unprocessable_content)
      end
      it "does not update location if city is blank" do
        patch business_manager_settings_location_path(location), params: { location: { city: "" } }
        expect(response).to have_http_status(:unprocessable_content)
      end
      it "does not update location if state is blank" do
        patch business_manager_settings_location_path(location), params: { location: { state: "" } }
        expect(response).to have_http_status(:unprocessable_content)
      end
      it "does not update location if zip is blank" do
        patch business_manager_settings_location_path(location), params: { location: { zip: "" } }
        expect(response).to have_http_status(:unprocessable_content)
      end
      it "does not update location if hours is blank" do
        patch business_manager_settings_location_path(location), params: { location: { hours: "" } }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "DELETE /destroy" do
    it "destroys the requested location" do
      expect do
        delete business_manager_settings_location_path(location)
      end.to change(Location, :count).by(-1)
    end

    it "redirects to the locations list" do
      delete business_manager_settings_location_path(location)
      expect(response).to redirect_to(business_manager_settings_locations_path)
    end
  end
end 
