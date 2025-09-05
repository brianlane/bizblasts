# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StaffController, type: :controller do
  let(:business) { create(:business) }
  let(:user) { create(:user, :manager, business: business) }
  let(:staff_member) { create(:staff_member, business: business) }
  let(:service) { create(:service, business: business) }
  let(:date) { Date.today }
  
  before do
    # Sign in the user
    sign_in user
    
    # Set up staff-service association
    create(:services_staff_member, service: service, staff_member: staff_member)
    
    # Set tenant context
    ActsAsTenant.current_tenant = business
    allow(controller).to receive(:current_business_scope).and_return(business)
    allow(controller).to receive(:current_user).and_return(user)
  end
  
  describe "GET #index" do
    it "returns a successful response" do
      get :index, format: :json
      expect(response).to be_successful
    end
    
    it "assigns all staff members" do
      get :index, format: :json
      expect(assigns(:staff_members)).to include(staff_member)
    end
  end
  
  describe "GET #show" do
    it "returns a successful response" do
      get :show, params: { id: staff_member.id }, format: :json
      expect(response).to be_successful
    end
    
    it "assigns the requested staff member" do
      get :show, params: { id: staff_member.id }, format: :json
      expect(assigns(:staff_member)).to eq(staff_member)
    end
    
    it "assigns upcoming bookings" do
      get :show, params: { id: staff_member.id }, format: :json
      expect(assigns(:upcoming_bookings)).to be_an(ActiveRecord::Relation)
    end
  end
  
  describe "GET #availability" do
    it "returns a successful response" do
      get :availability, params: { id: staff_member.id }, format: :json
      expect(response).to be_successful
    end
    
    it "assigns the requested staff member" do
      get :availability, params: { id: staff_member.id }, format: :json
      expect(assigns(:staff_member)).to eq(staff_member)
    end
    
    it "assigns the date" do
      get :availability, params: { id: staff_member.id, date: date.to_s }, format: :json
      expect(assigns(:date)).to eq(date)
    end
    
    it "assigns the start_date and end_date for week view" do
      get :availability, params: { id: staff_member.id, date: date.to_s }, format: :json
      expect(assigns(:start_date)).to eq(date.beginning_of_week)
      expect(assigns(:end_date)).to eq(date.end_of_week)
    end
    
    it "assigns the calendar_data" do
      allow(AvailabilityService).to receive(:availability_calendar).and_return({
        date.to_s => [{ start_time: Time.current, end_time: Time.current + 1.hour }]
      })
      
      get :availability, params: { id: staff_member.id, date: date.to_s }, format: :json
      
      expect(assigns(:calendar_data)).to be_present
    end
    
    it "assigns the services" do
      get :availability, params: { id: staff_member.id }, format: :json
      expect(assigns(:services)).to include(service)
    end
  end
  
  describe "PATCH #update_availability" do
    let(:valid_availability) do
      {
        'monday' => [{ 'start' => '09:00', 'end' => '17:00' }],
        'tuesday' => [{ 'start' => '09:00', 'end' => '17:00' }],
        'wednesday' => [{ 'start' => '09:00', 'end' => '17:00' }],
        'thursday' => [{ 'start' => '09:00', 'end' => '17:00' }],
        'friday' => [{ 'start' => '09:00', 'end' => '17:00' }],
        'saturday' => [],
        'sunday' => [],
        'exceptions' => {}
      }
    end
    
    context "with valid params" do
      it "updates the staff member's availability" do
        # Initialize staff member with valid availability structure
        staff_member.update(availability: {
          'monday' => [],
          'tuesday' => [],
          'wednesday' => [],
          'thursday' => [],
          'friday' => [],
          'saturday' => [],
          'sunday' => [],
          'exceptions' => {}
        })
        
        # Build params in the new indexed-hash format expected by the controller
        param_availability = valid_availability.transform_values do |slots|
          if slots.is_a?(Array)
            slots.each_with_index.map { |slot, idx| [idx.to_s, slot] }.to_h
          else
            slots
          end
        end

        patch :update_availability, params: {
          id: staff_member.id,
          staff_member: { availability: param_availability }
        }, format: :json
        
        # Reload the staff member to get the updated attributes
        staff_member.reload
        expect(staff_member.availability['monday']).to eq(valid_availability['monday'])
      end
      
      it "returns a success status and message" do
        param_availability = valid_availability.transform_values do |slots|
          if slots.is_a?(Array)
            slots.each_with_index.map { |slot, idx| [idx.to_s, slot] }.to_h
          else
            slots
          end
        end

        patch :update_availability, params: {
          id: staff_member.id,
          staff_member: { availability: param_availability }
        }, format: :json
        
        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be true
        expect(json_response['message']).to eq('Availability was successfully updated.')
      end
    end
    
    context "with invalid params" do
      let(:invalid_availability) do
        {
          'monday' => { '0' => { 'start' => '17:00', 'end' => '09:00' } } # End time before start time
        }
      end
      
      before do
        # Mock the validation error
        allow_any_instance_of(StaffMember).to receive(:update).and_return(false)
        allow_any_instance_of(StaffMember).to receive_message_chain(:errors, :full_messages).and_return(['Error message'])
      end
      
      it "returns an error status and messages" do
        patch :update_availability, params: {
          id: staff_member.id,
          staff_member: { availability: invalid_availability }
        }, format: :json
        
        expect(response).to have_http_status(:unprocessable_content)
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be false
        expect(json_response['errors']).to include('Error message')
      end
      
      it "assigns calendar_data for the view" do
        calendar_data = { Date.today.to_s => [{ start_time: Time.current, end_time: Time.current + 1.hour }] }
        allow(AvailabilityService).to receive(:availability_calendar).and_return(calendar_data)
        
        patch :update_availability, params: {
          id: staff_member.id,
          staff_member: { availability: invalid_availability }
        }, format: :json
        
        expect(assigns(:calendar_data)).to eq(calendar_data)
      end
    end
  end
end 