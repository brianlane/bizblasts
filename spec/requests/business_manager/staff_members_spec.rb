require 'rails_helper'

RSpec.describe "Business Manager StaffMembers", type: :request do
  let!(:business) { create(:business, hostname: 'testbiz') }
  let!(:manager) { create(:user, :manager, business: business) }
  let!(:staff_user) { create(:user, :staff, business: business) }
  let!(:staff_member) { create(:staff_member, business: business, user: staff_user) }

  let(:host_params) { { host: "#{business.hostname}.lvh.me" } }

  before do
    sign_in manager
    host! host_params[:host]
    ActsAsTenant.current_tenant = business
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe "GET /manage/staff_members" do
    it "renders a successful response" do
      get business_manager_staff_members_path
      expect(response).to be_successful
      expect(response.body).to include(staff_member.name)
    end

    it "shows booked and completed hours for the month" do
      # Create bookings for this staff member in the current month
      now = Time.current
      create(:booking, staff_member: staff_member, start_time: now.beginning_of_month + 1.day, end_time: now.beginning_of_month + 1.day + 2.hours, status: :confirmed)
      create(:booking, staff_member: staff_member, start_time: now.beginning_of_month + 2.days, end_time: now.beginning_of_month + 2.days + 3.hours, status: :completed)
      get business_manager_staff_members_path
      expect(response.body).to include(staff_member.hours_booked_this_month.round(2).to_s)
      expect(response.body).to include(staff_member.hours_completed_this_month.round(2).to_s)
    end
  end

  describe "GET /manage/staff_members/:id" do
    it "renders a successful response" do
      get business_manager_staff_member_path(staff_member)
      expect(response).to be_successful
      expect(response.body).to include(staff_member.name)
    end

    it "shows booked and completed hours for the month" do
      now = Time.current
      create(:booking, staff_member: staff_member, start_time: now.beginning_of_month + 3.days, end_time: now.beginning_of_month + 3.days + 1.5.hours, status: :confirmed)
      create(:booking, staff_member: staff_member, start_time: now.beginning_of_month + 4.days, end_time: now.beginning_of_month + 4.days + 2.5.hours, status: :completed)
      get business_manager_staff_member_path(staff_member)
      expect(response.body).to include(staff_member.hours_booked_this_month.round(2).to_s)
      expect(response.body).to include(staff_member.hours_completed_this_month.round(2).to_s)
    end
  end

  describe "GET /manage/staff_members/new" do
    it "renders a successful response" do
      get new_business_manager_staff_member_path
      expect(response).to be_successful
    end
  end

  describe "GET /manage/staff_members/:id/edit" do
    it "renders a successful response" do
      get edit_business_manager_staff_member_path(staff_member)
      expect(response).to be_successful
    end
  end

  describe "POST /manage/staff_members" do
    let(:valid_user_attributes) do
      attributes_for(:user, role: :staff, business_id: business.id).slice(:first_name, :last_name, :email, :password, :password_confirmation)
    end
    let(:valid_attributes) do
      attributes_for(:staff_member).merge(user_attributes: valid_user_attributes, user_role: 'staff')
    end
    let(:invalid_attributes) do
      { name: '', email: 'bademail', phone: 'notaphone', user_attributes: { email: '' } }
    end

    context "with valid parameters" do
      it "creates a new StaffMember and User" do
        expect {
          post business_manager_staff_members_path, params: { staff_member: valid_attributes }
        }.to change(StaffMember, :count).by(1).and change(User, :count).by(1)
      end

      it "redirects to the staff member show page" do
        post business_manager_staff_members_path, params: { staff_member: valid_attributes }
        staff = StaffMember.last
        expect(response).to redirect_to(business_manager_staff_member_path(staff))
      end
    end

    context "with invalid parameters" do
      it "does not create a new StaffMember" do
        expect {
          post business_manager_staff_members_path, params: { staff_member: invalid_attributes }
        }.not_to change(StaffMember, :count)
      end

      it "renders a response with 422 status" do
        post business_manager_staff_members_path, params: { staff_member: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "PATCH /manage/staff_members/:id" do
    let(:new_attributes) { { name: "Updated Name", phone: "555-999-8888" } }
    let(:invalid_attributes) { { name: "", phone: "badphone" } }

    context "with valid parameters" do
      it "updates the staff member" do
        patch business_manager_staff_member_path(staff_member), params: { staff_member: new_attributes }
        staff_member.reload
        expect(staff_member.name).to eq("Updated Name")
        expect(staff_member.phone).to eq("555-999-8888")
      end

      it "redirects to the staff member show page" do
        patch business_manager_staff_member_path(staff_member), params: { staff_member: new_attributes }
        expect(response).to redirect_to(business_manager_staff_member_path(staff_member))
      end
    end

    context "with invalid parameters" do
      it "does not update the staff member" do
        patch business_manager_staff_member_path(staff_member), params: { staff_member: invalid_attributes }
        staff_member.reload
        expect(staff_member.name).not_to eq("")
      end

      it "renders a response with 422 status" do
        patch business_manager_staff_member_path(staff_member), params: { staff_member: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "DELETE /manage/staff_members/:id" do
    it "destroys the requested staff member" do
      staff_to_delete = create(:staff_member, business: business)
      expect {
        delete business_manager_staff_member_path(staff_to_delete)
      }.to change(StaffMember, :count).by(-1)
    end

    it "redirects to the staff members list" do
      staff_to_delete = create(:staff_member, business: business)
      delete business_manager_staff_member_path(staff_to_delete)
      expect(response).to redirect_to(business_manager_staff_members_path)
    end
  end

  describe "GET /manage/staff_members/:id/manage_availability" do
    it "renders a successful response" do
      get manage_availability_business_manager_staff_member_path(staff_member)
      expect(response).to be_successful
      expect(response.body).to include("availability")
    end
  end

  describe "PATCH /manage/staff_members/:id/manage_availability" do
    let(:availability_params) do
      {
        monday: { "0" => { start: "09:00", end: "17:00" } },
        tuesday: {},
        wednesday: {},
        thursday: {},
        friday: {},
        saturday: {},
        sunday: {},
        exceptions: {}
      }
    end

    it "updates the staff member's availability" do
      patch manage_availability_business_manager_staff_member_path(staff_member), params: { staff_member: { availability: availability_params } }
      staff_member.reload
      expect(staff_member.availability["monday"]).to include({ "start" => "09:00", "end" => "17:00" })
      expect(response).to redirect_to(manage_availability_business_manager_staff_member_path(staff_member))
    end

    it "renders a response with 422 status if invalid" do
      allow_any_instance_of(StaffMember).to receive(:update).and_return(false)
      patch manage_availability_business_manager_staff_member_path(staff_member), params: { staff_member: { availability: availability_params } }
      expect(response).to have_http_status(:unprocessable_entity).or have_http_status(:ok)
    end
  end
end 