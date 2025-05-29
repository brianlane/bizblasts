# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "BusinessManager::Settings Account Deletion", type: :request do
  describe "DELETE /manage/settings/profile" do
    let(:business) { create(:business) }
    
    before do
      # Simulate subdomain in host for routes under SubdomainConstraint
      host! "#{business.hostname}.example.com"
      # Set current tenant for the request context
      ActsAsTenant.current_tenant = business
    end

    after do
      # Clear current tenant after the test
      ActsAsTenant.current_tenant = nil
    end

    context "when user is a staff member" do
      let(:staff_user) { create(:user, :staff, business: business) }
      let!(:staff_member) { create(:staff_member, business: business, user: staff_user) }

      before do
        sign_in staff_user
      end

      it "successfully deletes the staff account" do
        expect {
          delete business_manager_settings_profile_path, params: { 
            user: { 
              current_password: 'password123',
              confirm_deletion: 'DELETE' 
            } 
          }
        }.to change(User, :count).by(-1)
         .and change(StaffMember, :count).by(-1)

        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to include('account has been deleted')
      end

      it "handles staff with future bookings" do
        future_booking = create(:booking, 
          business: business, 
          staff_member: staff_member,
          start_time: 1.week.from_now
        )

        expect {
          delete business_manager_settings_profile_path, params: { 
            user: { 
              current_password: 'password123',
              confirm_deletion: 'DELETE' 
            } 
          }
        }.to change(User, :count).by(-1)

        # Booking should remain but staff nullified
        future_booking.reload
        expect(future_booking.staff_member_id).to be_nil
      end
    end

    context "when user is a manager with other managers" do
      let(:manager_user) { create(:user, :manager, business: business) }
      let!(:other_manager) { create(:user, :manager, business: business) }

      before do
        sign_in manager_user
      end

      it "successfully deletes the manager account" do
        expect {
          delete business_manager_settings_profile_path, params: { 
            user: { 
              current_password: 'password123',
              confirm_deletion: 'DELETE' 
            } 
          }
        }.to change(User, :count).by(-1)

        expect(response).to redirect_to(root_path)
        expect(Business.exists?(business.id)).to be true
      end
    end

    context "when user is the sole manager" do
      let(:manager_user) { create(:user, :manager, business: business) }
      let(:staff_user) { create(:user, :staff, business: business) }
      let!(:staff_member_without_user) { create(:staff_member, business: business, user: nil) }
      let!(:staff_member_with_user) { create(:staff_member, business: business, user: staff_user) }

      before do
        sign_in manager_user
      end

      it "prevents deletion without business deletion confirmation" do
        expect {
          delete business_manager_settings_profile_path, params: { 
            user: { 
              current_password: 'password123',
              confirm_deletion: 'DELETE' 
            } 
          }
        }.not_to change(User, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(flash[:alert]).to include('sole manager')
      end
    end

    context "when user is the sole user" do
      let(:manager_user) { create(:user, :manager, business: business) }

      before do
        sign_in manager_user
      end

      it "prevents deletion without business deletion confirmation" do
        expect {
          delete business_manager_settings_profile_path, params: { 
            user: { 
              current_password: 'password123',
              confirm_deletion: 'DELETE' 
            } 
          }
        }.not_to change(User, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(flash[:alert]).to include('sole user')
      end

      it "deletes manager and business when confirmed" do
        expect {
          delete business_manager_settings_profile_path, params: { 
            user: { 
              current_password: 'password123',
              confirm_deletion: 'DELETE',
              delete_business: '1'
            } 
          }
        }.to change(User, :count).by(-1)
         .and change(Business, :count).by(-1)

        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to include('account and business have been deleted')
      end
    end

    context "with invalid password" do
      let(:manager_user) { create(:user, :manager, business: business) }

      before do
        sign_in manager_user
      end

      it "does not delete the account" do
        expect {
          delete business_manager_settings_profile_path, params: { 
            user: { 
              current_password: 'wrongpassword',
              confirm_deletion: 'DELETE' 
            } 
          }
        }.not_to change(User, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(flash[:alert]).to include('Current password is incorrect')
      end
    end
  end

  describe "GET /manage/settings/profile - account deletion check" do
    let(:business) { create(:business) }
    
    before do
      # Simulate subdomain in host for routes under SubdomainConstraint
      host! "#{business.hostname}.example.com"
      # Set current tenant for the request context
      ActsAsTenant.current_tenant = business
    end

    after do
      # Clear current tenant after the test
      ActsAsTenant.current_tenant = nil
    end

    context "for sole manager" do
      let(:manager_user) { create(:user, :manager, business: business) }

      before do
        sign_in manager_user
      end

      it "shows business deletion warning" do
        get edit_business_manager_settings_profile_path
        
        expect(response).to have_http_status(:success)
        expect(response.body).to include('This will also delete the business')
        expect(response.body).to include('delete_business')
      end
    end

    context "for staff with future bookings" do
      let(:staff_user) { create(:user, :staff, business: business) }
      let!(:staff_member) { create(:staff_member, business: business, user: staff_user) }

      before do
        sign_in staff_user
        create(:booking, 
          business: business, 
          staff_member: staff_member,
          start_time: 1.week.from_now
        )
      end

      it "shows future booking warning" do
        get edit_business_manager_settings_profile_path
        
        expect(response).to have_http_status(:success)
        expect(response.body).to include('future booking')
      end
    end
  end

  describe "StaffMember deletion via business interface" do
    let(:business) { create(:business) }
    let(:manager_user) { create(:user, :manager, business: business) }
    let(:staff_user) { create(:user, :staff, business: business) }
    let!(:staff_member) { create(:staff_member, business: business, user: staff_user) }
    
    before do
      # Simulate subdomain in host for routes under SubdomainConstraint
      host! "#{business.hostname}.example.com"
      # Set current tenant for the request context
      ActsAsTenant.current_tenant = business
      sign_in manager_user
    end

    after do
      # Clear current tenant after the test
      ActsAsTenant.current_tenant = nil
    end

    it "deletes both staff member and associated user when manager deletes staff member" do
      expect {
        delete business_manager_staff_member_path(staff_member)
      }.to change(User, :count).by(-1)
       .and change(StaffMember, :count).by(-1)
      
      expect(response).to redirect_to(business_manager_staff_members_path)
      expect(flash[:notice]).to include('successfully removed')
    end
  end
end 