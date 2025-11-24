# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Client::Settings Account Deletion", type: :request do
  describe "DELETE /client/settings" do
    let(:client_user) { create(:user, :client, password: 'password123') }
    let(:business) { create(:business) }

    before do
      sign_in client_user
    end

    context "with valid password confirmation" do
      it "successfully deletes the account" do
        expect {
          delete client_settings_path, params: { 
            user: { 
              current_password: 'password123',
              confirm_deletion: 'DELETE' 
            } 
          }
        }.to change(User, :count).by(-1)

        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to include('account has been deleted')
      end

      it "handles client with business associations" do
        create(:client_business, user: client_user, business: business)
        
        expect {
          delete client_settings_path, params: { 
            user: { 
              current_password: 'password123',
              confirm_deletion: 'DELETE' 
            } 
          }
        }.to change(User, :count).by(-1)
         .and change(ClientBusiness, :count).by(-1)

        expect(Business.exists?(business.id)).to be true
      end
    end

    context "with invalid password" do
      it "does not delete the account" do
        expect {
          delete client_settings_path, params: { 
            user: { 
              current_password: 'wrongpassword',
              confirm_deletion: 'DELETE' 
            } 
          }
        }.not_to change(User, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(flash[:alert]).to include('Current password is incorrect')
      end
    end

    context "without deletion confirmation" do
      it "does not delete the account" do
        expect {
          delete client_settings_path, params: { 
            user: { 
              current_password: 'password123' 
            } 
          }
        }.not_to change(User, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(flash[:alert]).to include('must type DELETE')
      end
    end

    context "when not authenticated" do
      before { sign_out client_user }

      it "redirects to sign in" do
        delete client_settings_path, params: { user: { current_password: 'password123', confirm_deletion: 'DELETE' } }
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe "GET /client/settings - deletion form" do
    let(:client_user) { create(:user, :client) }

    before do
      sign_in client_user
    end

    it "shows the account deletion section" do
      get client_settings_path
      
      expect(response).to have_http_status(:success)
      expect(response.body).to include('Delete Account')
      expect(response.body).to include('This action cannot be undone')
      expect(response.body).to include('current_password')
      expect(response.body).to include('confirm_deletion')
    end
  end
end 