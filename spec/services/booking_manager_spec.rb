# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BookingManager, type: :service do
  # Use ActiveJob test helpers for reminder checks
  include ActiveJob::TestHelper

  let!(:tenant) { create(:business) }
  let!(:customer) { create(:tenant_customer, business: tenant) }
  let!(:service) { create(:service, business: tenant, price: 50.00, duration: 60) }
  let!(:staff_member) { create(:staff_member, business: tenant) }
  
  # Define base times accessible to all contexts
  let(:start_time) { Time.current.beginning_of_hour + 2.days + 9.hours }
  let(:end_time) { start_time + service.duration.minutes }

  around do |example|
    ActsAsTenant.with_tenant(tenant) do
      # Ensure jobs are cleared before each example within tenant context
      clear_enqueued_jobs
      example.run
      # Ensure jobs are cleared after each example
      clear_enqueued_jobs 
    end
  end

  before do
    # Allow the availability service to always return true for testing
    allow(AvailabilityService).to receive(:is_available?).and_return(true)
    
    # Stub the mailer to prevent actual emails being sent
    allow_any_instance_of(ActionMailer::MessageDelivery).to receive(:deliver_later)
    allow_any_instance_of(ActionMailer::MessageDelivery).to receive(:deliver_now)
    allow(BookingMailer).to receive(:confirmation).and_return(double("mailer", deliver_later: true, deliver_now: true))
    allow(BookingMailer).to receive(:status_update).and_return(double("mailer", deliver_later: true, deliver_now: true))
    allow(BookingMailer).to receive(:cancellation).and_return(double("mailer", deliver_later: true, deliver_now: true))
    allow(BookingMailer).to receive(:reminder).and_return(double("mailer", deliver_later: true, deliver_now: true))
    
    # Stub the reminder job
    allow(BookingReminderJob).to receive(:set).and_return(BookingReminderJob)
    allow(BookingReminderJob).to receive(:perform_later)
  end

  describe '.create_booking' do
    let(:valid_params) do
      {
        service_id: service.id,
        staff_member_id: staff_member.id,
        tenant_customer_id: customer.id,
        start_time: Time.current + 1.day,
        notes: "Test booking"
      }
    end
    
    context 'with valid parameters' do
      it 'creates a new booking' do
        expect {
          booking, errors = BookingManager.create_booking(valid_params, tenant)
          expect(booking).to be_persisted
          expect(errors).to be_nil
        }.to change(Booking, :count).by(1)
      end
      
      it 'calculates the end time based on service duration' do
        booking, _ = BookingManager.create_booking(valid_params, tenant)
        
        expect(booking.end_time).to eq(booking.start_time + service.duration.minutes)
      end
      
      it 'sets the status to pending by default' do
        booking, _ = BookingManager.create_booking(valid_params, tenant)
        
        expect(booking.status).to eq('pending')
      end
      
      it 'sets the correct amount based on service price' do
        booking, _ = BookingManager.create_booking(valid_params, tenant)
        
        expect(booking.amount).to eq(service.price)
        expect(booking.original_amount).to eq(service.price)
      end
    end
    
    context 'with customer information instead of tenant_customer_id' do
      let(:new_customer_params) do
        {
          service_id: service.id,
          staff_member_id: staff_member.id,
          customer_name: "New Customer",
          customer_email: "new@example.com",
          customer_phone: "123-456-7890",
          start_time: Time.current + 1.day,
          notes: "New customer booking"
        }
      end
      
      it 'creates a new tenant customer record' do
        expect {
          booking, errors = BookingManager.create_booking(new_customer_params, tenant)
          
          expect(booking).to be_persisted
          expect(errors).to be_nil
          expect(booking.tenant_customer).to be_present
          expect(booking.tenant_customer.name).to eq("New Customer")
          expect(booking.tenant_customer.email).to eq("new@example.com")
          expect(booking.tenant_customer.phone).to eq("123-456-7890")
        }.to change(TenantCustomer, :count).by(1)
      end
      
      it 'finds an existing tenant customer by email' do
        existing_customer = create(:tenant_customer, business: tenant, 
                                  name: "Existing Customer", email: "new@example.com")
        
        expect {
          booking, errors = BookingManager.create_booking(new_customer_params, tenant)
          
          expect(booking).to be_persisted
          expect(errors).to be_nil
          expect(booking.tenant_customer).to eq(existing_customer)
        }.not_to change(TenantCustomer, :count)
      end
    end
    
    context 'with date and time parameters' do
      let(:datetime_params) do
        {
          service_id: service.id,
          staff_member_id: staff_member.id,
          tenant_customer_id: customer.id,
          date: Date.today + 1.day,
          time: "14:30",
          notes: "Booking with date and time"
        }
      end
      
      it 'correctly processes date and time into start_time' do
        booking, errors = BookingManager.create_booking(datetime_params, tenant)
        
        expect(booking).to be_persisted
        expect(errors).to be_nil
        
        # Check that the start_time matches the date and time provided
        expected_datetime = Time.zone.local(
          datetime_params[:date].year,
          datetime_params[:date].month,
          datetime_params[:date].day,
          14, 30
        )
        
        expect(booking.start_time).to be_within(1.second).of(expected_datetime)
      end
    end
    
    context 'with a time conflict' do
      it 'returns an error if the time is not available' do
        # Mock the availability service to return false
        allow(AvailabilityService).to receive(:is_available?).and_return(false)
        
        booking, errors = BookingManager.create_booking(valid_params, tenant)
        
        expect(booking).to be_nil
        expect(errors.full_messages).to include("The selected time is not available for this staff member")
      end
    end
    
    context 'with missing required parameters' do
      it 'returns an error if service_id is missing' do
        params = valid_params.except(:service_id)
        
        booking, errors = BookingManager.create_booking(params, tenant)
        
        expect(booking).to be_nil
        expect(errors.full_messages).to include(/Service can't be blank/)
      end
      
      it 'returns an error if staff_member_id is missing' do
        params = valid_params.except(:staff_member_id)
        
        booking, errors = BookingManager.create_booking(params, tenant)
        
        expect(booking).to be_nil
        expect(errors.full_messages).to include(/Staff member can't be blank/)
      end
    end
  end
  
  describe '.update_booking' do
    let!(:booking) { 
      create(:booking, 
             business: tenant, 
             service: service, 
             staff_member: staff_member, 
             tenant_customer: customer,
             start_time: Time.current + 1.day,
             end_time: Time.current + 1.day + 1.hour,
             status: :pending) 
    }
    
    before do
      # Allow any instance of StaffMember to respond to services association
      allow_any_instance_of(StaffMember).to receive(:services).and_return([service])
      
      # Allow validation methods to pass
      allow_any_instance_of(Booking).to receive(:valid?).and_return(true)
    end
    
    context 'with valid parameters' do
      it 'updates the booking' do
        new_start_time = Time.current + 2.days
        
        # Allow find_by to return a staff member
        allow(StaffMember).to receive(:find_by).and_return(staff_member)
        
        updated_booking, errors = BookingManager.update_booking(booking, { start_time: new_start_time })
        
        expect(updated_booking).to eq(booking)
        expect(errors).to be_nil
        expect(updated_booking.start_time).to eq(new_start_time)
      end
      
      it 'recalculates end_time when start_time changes' do
        new_start_time = Time.current + 2.days
        
        # Allow Service find_by to return a service with duration
        allow(Service).to receive(:find_by).and_return(service)
        allow(StaffMember).to receive(:find_by).and_return(staff_member)
        
        updated_booking, errors = BookingManager.update_booking(booking, { start_time: new_start_time })
        
        expect(updated_booking).to eq(booking)
        expect(errors).to be_nil
        expect(updated_booking.end_time).to eq(new_start_time + service.duration.minutes)
      end
      
      it 'recalculates end_time when service changes' do
        new_service = create(:service, business: tenant, duration: 90, price: 150)
        
        # Allow Service find_by to return the new service
        allow(Service).to receive(:find_by).and_return(new_service)
        allow(StaffMember).to receive(:find_by).and_return(staff_member)
        
        updated_booking, errors = BookingManager.update_booking(booking, { service_id: new_service.id })
        
        expect(updated_booking).to eq(booking)
        expect(errors).to be_nil
        expect(updated_booking.end_time).to eq(updated_booking.start_time + 90.minutes)
      end
    end
    
    context 'with time conflict' do
      it 'returns an error if the new time is not available' do
        # Mock the availability service to return false
        allow(AvailabilityService).to receive(:is_available?).and_return(false)
        allow(StaffMember).to receive(:find_by).and_return(staff_member)
        
        new_start_time = Time.current + 3.days
        updated_booking, errors = BookingManager.update_booking(booking, { start_time: new_start_time })
        
        expect(updated_booking).to be_nil
        expect(errors.full_messages).to include("The selected time is not available for this staff member")
      end
    end
    
    context 'with date and time parameters' do
      it 'correctly processes date and time into start_time' do
        date = Date.today + 2.days
        time = "16:45"
        
        allow(StaffMember).to receive(:find_by).and_return(staff_member)
        
        updated_booking, errors = BookingManager.update_booking(booking, { date: date, time: time })
        
        expect(updated_booking).to eq(booking)
        expect(errors).to be_nil
        
        # Check that the start_time matches the date and time provided
        expected_datetime = Time.zone.local(date.year, date.month, date.day, 16, 45)
        expect(updated_booking.start_time).to be_within(1.second).of(expected_datetime)
      end
    end
    
    context 'with status change' do
      it 'updates the status' do
        allow(StaffMember).to receive(:find_by).and_return(staff_member)
        
        updated_booking, errors = BookingManager.update_booking(booking, { status: :confirmed })
        
        expect(updated_booking).to eq(booking)
        expect(errors).to be_nil
        expect(updated_booking.status).to eq('confirmed')
      end
    end
  end
  
  describe '.cancel_booking' do
    let!(:booking) { 
      create(:booking, 
             business: tenant, 
             service: service, 
             staff_member: staff_member, 
             tenant_customer: customer,
             start_time: Time.current + 1.day,
             end_time: Time.current + 1.day + 1.hour,
             status: :confirmed) 
    }
    
    it 'cancels the booking' do
      result = BookingManager.cancel_booking(booking)
      
      expect(result).to be true
      expect(booking.reload.status).to eq('cancelled')
    end
    
    it 'sets the cancellation reason' do
      reason = "Customer requested cancellation"
      result = BookingManager.cancel_booking(booking, reason)
      
      expect(result).to be true
      expect(booking.reload.status).to eq('cancelled')
      expect(booking.cancellation_reason).to eq(reason)
    end
    
    it 'returns false if booking cannot be cancelled' do
      # Make the booking update fail
      allow(booking).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(booking))
      
      result = BookingManager.cancel_booking(booking)
      
      expect(result).to be false
    end
  end
  
  describe '.available?' do
    it 'delegates to AvailabilityService' do
      start_time = Time.current + 1.day
      end_time = start_time + 1.hour
      
      expect(AvailabilityService).to receive(:is_available?).with(
        staff_member: staff_member,
        start_time: start_time,
        end_time: end_time,
        exclude_booking_id: 123
      )
      
      BookingManager.available?(
        staff_member: staff_member,
        start_time: start_time,
        end_time: end_time,
        exclude_booking_id: 123
      )
    end
  end
end 