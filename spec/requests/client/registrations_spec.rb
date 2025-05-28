# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Client::Registrations", type: :request do
  describe "POST /client" do
    let(:valid_attributes) do
      {
        user: {
          first_name: "Test",
          last_name: "Client",
          email: "client@example.com",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end

    let(:invalid_attributes) do
      {
        user: {
          first_name: "Test",
          last_name: "Client",
          email: "invalid-email",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end

    context "with valid parameters" do
      it "creates a new User with client role" do
        expect {
          post client_registration_path, params: valid_attributes
        }.to change(User, :count).by(1)
        
        new_user = User.last
        expect(new_user.email).to eq("client@example.com")
        expect(new_user.first_name).to eq("Test")
        expect(new_user.last_name).to eq("Client")
        expect(new_user.client?).to be true
        expect(new_user.business).to be_nil
      end

      it "redirects to the root path after sign up" do
        post client_registration_path, params: valid_attributes
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq("A message with a confirmation link has been sent to your email address. Please follow the link to activate your account.")
      end

      it "does not sign in the user immediately (requires email confirmation)" do
        post client_registration_path, params: valid_attributes
        expect(controller.current_user).to be_nil
      end
    end

    context "with invalid parameters" do
      it "does not create a new User" do
        expect {
          post client_registration_path, params: invalid_attributes
        }.not_to change(User, :count)
      end

      it "re-renders the 'new' template with errors" do
        post client_registration_path, params: invalid_attributes
        expect(response).to have_http_status(:unprocessable_entity) 
        expect(response.body).to include("Email is invalid") # Check for specific error message
      end
    end

    context "when email is already taken by another client" do
      let!(:existing_client) { create(:user, role: :client, email: "client@example.com") }

      it "does not create a new User" do
        expect {
          post client_registration_path, params: valid_attributes
        }.not_to change(User, :count)
      end

      it "re-renders the 'new' template with email taken error" do
        post client_registration_path, params: { user: attributes_for(:user, :client, email: existing_client.email) }
        expect(response).to render_template(:new)
        expect(response.body).to include("Email has already been taken")
      end
    end

    context "when email is taken by a business user" do
      let!(:existing_manager) { create(:user, role: :manager, email: "client@example.com", business: create(:business)) }

      it "does NOT create a new client User" do 
        expect {
          post client_registration_path, params: valid_attributes
        }.not_to change(User, :count)
      end

      it "re-renders the new template with the email taken error" do
        post client_registration_path, params: valid_attributes
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Email has already been taken")
      end
    end
  end
end 