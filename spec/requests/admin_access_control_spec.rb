# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Admin Access Control", type: :request do
  # Use FactoryBot
  include FactoryBot::Syntax::Methods

  let!(:admin_user) { create(:admin_user) }
  let!(:user) { create(:user) }

  describe "Authentication" do
    it "redirects non-authenticated users to the login page" do
      get admin_businesses_path
      expect(response).to redirect_to(new_admin_user_session_path)
    end

    it "allows authenticated AdminUser access" do
      sign_in admin_user
      get admin_businesses_path
      expect(response).to have_http_status(:ok)
    end

    it "redirects authenticated standard User to root (or appropriate path)" do
      # Standard Devise behavior might redirect to root or user dashboard
      # We just need to ensure they *don't* get into /admin
      sign_in user
      get admin_businesses_path
      # Expect redirect away from admin, typically to root or new_admin_user_session
      expect(response).to redirect_to(new_admin_user_session_path)
    end
  end

  describe "Authorization (Pundit - Basic)" do
    before do
      sign_in admin_user
    end

    context "when accessing Business index" do
      it "allows access" do
        get admin_businesses_path
        expect(response).to have_http_status(:ok)
      end
    end
    
    # Add more contexts for other resources (e.g., Users, Services) as needed
    # Add tests for specific actions (show, edit, destroy) if policies become more granular
    
    # Example of testing a non-admin user (though authentication should catch this first)
    # context "when a non-admin user attempts access" do
    #   before do
    #     sign_out admin_user
    #     sign_in user
    #   end
    #   it "redirects or raises forbidden error" do
    #     # Depending on Pundit setup, this might redirect or raise Pundit::NotAuthorizedError
    #     # For ActiveAdmin, it often redirects back to login due to authentication_method
    #     get admin_businesses_path
    #     expect(response).to redirect_to(new_admin_user_session_path)
    #   end
    # end
  end
end 