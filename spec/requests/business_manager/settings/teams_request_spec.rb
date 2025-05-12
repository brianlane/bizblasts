# frozen_string_literal: true

require 'rails_helper'
require 'devise/test/integration_helpers'

RSpec.describe "BusinessManager::Settings::Teams", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:business) { create(:business) }
  let(:manager_user) { create(:user, :manager, business: business) }
  let(:staff_user) { create(:user, :staff, business: business) }
  let!(:staff_member) { create(:staff_member, business: business, user: staff_user) }

  before do
    host! "#{business.hostname}.lvh.me"
    ActsAsTenant.current_tenant = business
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe "GET /manage/settings/teams" do
    subject { get business_manager_settings_teams_path }

    context "as manager" do
      before { sign_in manager_user }
      it "renders successfully" do
        subject
        expect(response).to be_successful
        expect(response.body).to include("Team & Access Control")
        expect(response.body).to include(staff_member.email)
      end
    end

    context "as staff" do
      before { sign_in staff_user }
      it "renders successfully" do
        subject
        expect(response).to be_successful
        expect(response.body).to include(staff_user.email)
      end
    end
  end

  describe "GET /manage/settings/teams/new" do
    subject { get new_business_manager_settings_team_path }

    context "as manager" do
      before { sign_in manager_user }
      it "renders successfully" do
        subject
        expect(response).to be_successful
        expect(response.body).to include("Invite Team Member").or include("Name")
      end
    end

    context "as staff" do
      before { sign_in staff_user }
      it "is forbidden" do
        subject
        expect(response).to have_http_status(:forbidden).or have_http_status(:redirect)
      end
    end
  end

  describe "POST /manage/settings/teams" do
    let(:invite_params) do
      {
        staff_member: {
          name: "New Staff",
          phone: "555-1234",
          position: "",
          user_attributes: {
            first_name: "New",
            last_name: "Staff",
            email: "newstaff@example.com",
            password: "password",
            password_confirmation: "password"
          }
        }
      }
    end
    subject { post business_manager_settings_teams_path, params: invite_params }

    context "as manager" do
      before { sign_in manager_user }
      it "creates a new staff member and user" do
        expect { subject }.to change(StaffMember, :count).by(1).and change(User, :count).by(1)
        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(business_manager_settings_teams_path)
        follow_redirect!
        expect(response.body).to include("Team member invited successfully.")
        expect(response.body).to include("New Staff")
      end
    end

    context "as staff" do
      before { sign_in staff_user }
      it "is forbidden" do
        subject
        expect(response).to have_http_status(:forbidden).or have_http_status(:redirect)
      end
    end
  end

  describe "DELETE /manage/settings/teams/:id" do
    let!(:removable) { create(:staff_member, business: business) }
    subject { delete business_manager_settings_team_path(removable) }

    context "as manager" do
      before { sign_in manager_user }
      it "removes the staff member" do
        expect { subject }.to change(StaffMember, :count).by(-1)
        expect(response).to redirect_to(business_manager_settings_teams_path)
        follow_redirect!
        expect(response.body).to include("Team member removed.")
      end
    end

    context "as staff" do
      before { sign_in staff_user }
      it "is forbidden" do
        subject
        expect(response).to have_http_status(:forbidden).or have_http_status(:redirect)
      end
    end
  end
end 