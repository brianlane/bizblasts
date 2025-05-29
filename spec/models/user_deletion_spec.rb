# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "User Account Deletion", type: :model do
  describe "User#destroy_account" do
    context "when user is a client" do
      let(:business) { create(:business) }
      let(:client_user) { create(:user, :client) }
      let!(:client_business) { create(:client_business, user: client_user, business: business) }
      let!(:tenant_customer) { create(:tenant_customer, business: business, email: client_user.email) }
      let!(:booking) { create(:booking, business: business, tenant_customer: tenant_customer) }
      let!(:invoice) { create(:invoice, business: business, tenant_customer: tenant_customer) }
      let!(:order) { create(:order, business: business, tenant_customer: tenant_customer) }

      it "successfully deletes client account with dependent associations" do
        expect {
          client_user.destroy_account
        }.to change(User, :count).by(-1)
        
        # Client businesses should be deleted
        expect(ClientBusiness.exists?(user: client_user)).to be false
        
        # Associated data should remain but be orphaned
        expect(TenantCustomer.exists?(tenant_customer.id)).to be true
        expect(Booking.exists?(booking.id)).to be true
        expect(Invoice.exists?(invoice.id)).to be true
        expect(Order.exists?(order.id)).to be true
      end

      it "handles multiple business associations" do
        business2 = create(:business)
        client_business2 = create(:client_business, user: client_user, business: business2)
        
        expect {
          client_user.destroy_account
        }.to change(User, :count).by(-1)
        
        expect(ClientBusiness.exists?(user: client_user)).to be false
      end
    end

    context "when user is a staff member" do
      let(:business) { create(:business) }
      let(:staff_user) { create(:user, :staff, business: business) }
      let!(:staff_member) { create(:staff_member, business: business, user: staff_user) }
      let!(:booking) { create(:booking, business: business, staff_member: staff_member) }
      let!(:service) { create(:service, business: business) }
      let!(:staff_assignment) { create(:staff_assignment, user: staff_user, service: service) }

      it "successfully deletes staff account and nullifies associations" do
        expect {
          staff_user.destroy_account
        }.to change(User, :count).by(-1)
         .and change(StaffMember, :count).by(-1)
        
        # Bookings should remain but staff_member association nullified
        booking.reload
        expect(booking.staff_member_id).to be_nil
        
        # Staff assignments should be deleted
        expect(StaffAssignment.exists?(user: staff_user)).to be false
      end

      it "handles booking constraints appropriately" do
        # Create a booking in the future
        future_booking = create(:booking, 
          business: business, 
          staff_member: staff_member,
          start_time: 1.week.from_now
        )
        
        staff_user.destroy_account
        
        # Future booking should have staff_member nullified
        future_booking.reload
        expect(future_booking.staff_member_id).to be_nil
      end
    end

    context "when user is a business manager" do
      let(:business) { create(:business) }
      let(:manager_user) { create(:user, :manager, business: business) }
      let!(:staff_member) { create(:staff_member, business: business, user: manager_user) }
      let!(:other_staff) { create(:staff_member, business: business) }
      let!(:other_manager) { create(:user, :manager, business: business) }

      context "with other managers present" do
        it "successfully deletes manager account" do
          expect {
            manager_user.destroy_account
          }.to change(User, :count).by(-1)
           .and change(StaffMember, :count).by(-1)
          
          # Business should remain
          expect(Business.exists?(business.id)).to be true
        end
      end

      context "as the sole manager" do
        before do
          other_manager.destroy
          # Create a staff user to ensure there are other users but no other managers
          @staff_user = create(:user, :staff, business: business)
          @staff_member_for_staff_user = create(:staff_member, business: business, user: @staff_user)
        end

        it "raises an error and prevents deletion" do
          expect {
            manager_user.destroy_account
          }.to raise_error(User::AccountDeletionError, /Cannot delete the sole manager/)
          
          expect(User.exists?(manager_user.id)).to be true
          expect(Business.exists?(business.id)).to be true
        end
      end

      context "as the sole user (manager and no staff)" do
        before do
          other_manager.destroy
          other_staff.destroy
        end

        it "deletes manager and offers business deletion" do
          result = manager_user.destroy_account(delete_business: true)
          
          expect(result[:deleted]).to be true
          expect(result[:business_deleted]).to be true
          expect(User.exists?(manager_user.id)).to be false
          expect(Business.exists?(business.id)).to be false
        end

        it "prevents deletion without business deletion confirmation" do
          expect {
            manager_user.destroy_account
          }.to raise_error(User::AccountDeletionError, /This will also delete the business/)
          
          expect(User.exists?(manager_user.id)).to be true
          expect(Business.exists?(business.id)).to be true
        end
      end
    end
  end

  describe "User#can_delete_account?" do
    context "for client users" do
      let(:client_user) { create(:user, :client) }

      it "returns true with no restrictions" do
        result = client_user.can_delete_account?
        expect(result[:can_delete]).to be true
        expect(result[:restrictions]).to be_empty
      end
    end

    context "for staff users" do
      let(:business) { create(:business) }
      let(:staff_user) { create(:user, :staff, business: business) }

      it "returns true with future booking warnings" do
        future_booking = create(:booking, 
          business: business,
          staff_member: create(:staff_member, business: business, user: staff_user),
          start_time: 1.week.from_now
        )
        
        result = staff_user.can_delete_account?
        expect(result[:can_delete]).to be true
        expect(result[:warnings]).to include(/1 future booking/)
      end
    end

    context "for manager users" do
      let(:business) { create(:business) }
      let(:manager_user) { create(:user, :manager, business: business) }

      context "when sole manager with staff" do
        let!(:staff_user) { create(:user, :staff, business: business) }

        it "returns false when sole manager" do
          result = manager_user.can_delete_account?
          expect(result[:can_delete]).to be false
          expect(result[:restrictions]).to include(/sole manager/)
        end
      end

      context "when sole user" do
        it "returns true with business deletion warning when sole user" do
          result = manager_user.can_delete_account?
          expect(result[:can_delete]).to be true
          expect(result[:warnings]).to include(/will also delete the business/)
        end
      end
    end
  end

  describe "Bidirectional StaffMember-User deletion" do
    let(:business) { create(:business) }
    let(:staff_user) { create(:user, :staff, business: business) }
    let(:staff_member) { create(:staff_member, business: business, user: staff_user) }

    context "when deleting a StaffMember with an associated User" do
      it "deletes the associated User" do
        staff_member # ensure it's created
        
        expect {
          staff_member.destroy
        }.to change(User, :count).by(-1)
         .and change(StaffMember, :count).by(-1)
        
        expect(User.exists?(staff_user.id)).to be false
      end
    end

    context "when deleting a StaffMember without an associated User" do
      let(:staff_member_no_user) { create(:staff_member, business: business, user: nil) }
      
      it "only deletes the StaffMember" do
        staff_member_no_user # ensure it's created
        
        expect {
          staff_member_no_user.destroy
        }.to change(StaffMember, :count).by(-1)
         .and change(User, :count).by(0)
      end
    end

    context "when deleting a User with an associated StaffMember" do
      it "deletes the associated StaffMember" do
        staff_member # ensure it's created
        
        expect {
          staff_user.destroy_account
        }.to change(User, :count).by(-1)
         .and change(StaffMember, :count).by(-1)
        
        expect(StaffMember.exists?(staff_member.id)).to be false
      end
    end
  end

  describe "Business deletion cascade" do
    let(:business) { create(:business) }
    let(:manager_user) { create(:user, :manager, business: business) }
    
    before do
      # Create various business data
      create(:service, business: business)
      create(:staff_member, business: business)
      create(:tenant_customer, business: business)
      create(:booking, business: business)
      create(:invoice, business: business)
      create(:order, business: business)
      create(:product, business: business)
    end

    it "properly cascades business deletion with foreign key constraints" do
      initial_counts = {
        services: Service.count,
        staff_members: StaffMember.count,
        tenant_customers: TenantCustomer.count,
        bookings: Booking.count,
        invoices: Invoice.count,
        orders: Order.count,
        products: Product.count
      }

      manager_user.destroy_account(delete_business: true)

      # Verify cascade deletions based on foreign key constraints
      expect(Service.count).to be < initial_counts[:services]
      expect(StaffMember.count).to be < initial_counts[:staff_members]
      expect(TenantCustomer.count).to be < initial_counts[:tenant_customers]
      expect(Product.count).to be < initial_counts[:products]
      
      # Items that should be orphaned (nullified foreign keys)
      expect(Booking.count).to eq(initial_counts[:bookings])
      expect(Invoice.count).to eq(initial_counts[:invoices])
      expect(Order.count).to eq(initial_counts[:orders])
    end
  end
end 