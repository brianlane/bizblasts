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

  describe '.create_booking' do
    let(:valid_booking_params) do
      {
        business_id: tenant.id,
        tenant_customer_id: customer.id,
        service_id: service.id,
        staff_member_id: staff_member.id,
        start_time: start_time,
        end_time: end_time,
        amount: service.price,
        status: :pending
        # Assuming send_confirmation and require_payment are passed here if needed
        # send_confirmation: true, 
        # require_payment: false 
      }
    end

    context 'when the time slot is available' do
      before do
        # Mock staff member availability check to return true
        allow(staff_member).to receive(:available?).with(start_time, end_time).and_return(true)
        # Need to ensure find returns the mockable staff_member
        allow(StaffMember).to receive(:find).with(staff_member.id).and_return(staff_member)
      end
      
      it 'creates a new booking' do
        expect {
          booking, errors = described_class.create_booking(valid_booking_params)
          expect(booking).to be_persisted
          expect(errors).to be_nil
        }.to change(Booking, :count).by(1)
        
        created_booking = Booking.last
        expect(created_booking.service).to eq(service)
        expect(created_booking.staff_member).to eq(staff_member)
        expect(created_booking.tenant_customer).to eq(customer)
        expect(created_booking.start_time).to eq(start_time)
        expect(created_booking.status).to eq('pending')
      end

      it 'schedules two booking reminders' do
        expect {
          described_class.create_booking(valid_booking_params)
        }.to have_enqueued_job(BookingReminderJob).twice
        
        # Check reminder times (approximate)
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs.count).to eq(2)
        # First reminder ~24h before
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs.first[:at].to_i).to be_within(1).of((start_time - 24.hours).to_i)
        # Second reminder ~1h before
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs.second[:at].to_i).to be_within(1).of((start_time - 1.hour).to_i)
      end
      
      # TODO: Add tests for send_confirmation and require_payment flags if implemented
      # TODO: Test StripeService interaction if uncommented
    end

    context 'when the time slot is not available' do
       before do
         # Mock staff member availability check to return false
         allow(staff_member).to receive(:available?).with(start_time, end_time).and_return(false)
         allow(StaffMember).to receive(:find).with(staff_member.id).and_return(staff_member)
       end
       
       it 'does not create a booking' do
         expect {
           booking, errors = described_class.create_booking(valid_booking_params)
           expect(booking).to be_nil
           expect(errors).not_to be_nil
           expect(errors[:base]).to include("The selected time is not available for this staff member")
         }.not_to change(Booking, :count)
       end
       
       it 'does not schedule any reminders' do
          expect {
            described_class.create_booking(valid_booking_params)
          }.not_to have_enqueued_job(BookingReminderJob)
       end
    end
    
    context 'when booking params are invalid (e.g., missing service)' do
      let(:invalid_params) { valid_booking_params.except(:service_id) }
      
      it 'does not create a booking and returns validation errors' do
        # Availability check might pass or fail depending on mock, but save should fail
        allow(staff_member).to receive(:available?).and_return(true)
        allow(StaffMember).to receive(:find).with(staff_member.id).and_return(staff_member)
        
        expect {
           booking, errors = described_class.create_booking(invalid_params)
           expect(booking).to be_nil
           expect(errors).not_to be_nil
           expect(errors[:service]).to include("must exist")
         }.not_to change(Booking, :count)
      end
    end
  end
  
  describe '.update_booking' do
    let!(:existing_booking) { create(:booking, business: tenant, tenant_customer: customer, service: service, staff_member: staff_member, start_time: start_time, end_time: end_time, status: :confirmed) }
    
    let(:new_start_time) { start_time + 1.hour } # Move to 10 AM
    let(:new_end_time) { new_start_time + service.duration.minutes }
    let(:update_params_no_time) { { notes: "Updated notes" } }
    let(:update_params_with_time) { { start_time: new_start_time, end_time: new_end_time, notes: "Rescheduled" } }
    let(:update_params_invalid) { { service_id: nil } }

    context 'when updating non-time attributes' do
      it 'updates the booking successfully' do
        booking, errors = described_class.update_booking(existing_booking, update_params_no_time)
        expect(errors).to be_nil
        expect(booking).to eq(existing_booking)
        expect(booking.notes).to eq("Updated notes")
      end

      it 'does not reschedule reminders' do
        # Need to check that existing reminders aren't cancelled/re-added
        # For now, just check no *new* jobs are enqueued
        expect {
          described_class.update_booking(existing_booking, update_params_no_time)
        }.not_to have_enqueued_job(BookingReminderJob)
      end
    end

    context 'when updating time to an available slot' do
      before do
        # Mock availability for the *new* time slot
        allow(staff_member).to receive(:available?).with(new_start_time, new_end_time).and_return(true)
        # No need to mock find, as update_booking uses booking.staff_member directly
      end

      it 'updates the booking start and end times' do
        booking, errors = described_class.update_booking(existing_booking, update_params_with_time)
        expect(errors).to be_nil
        expect(booking.start_time).to eq(new_start_time)
        expect(booking.end_time).to eq(new_end_time)
        expect(booking.notes).to eq("Rescheduled")
      end

      it 'reschedules two reminders for the new time' do
        # Service logic just enqueues new jobs
        expect {
          described_class.update_booking(existing_booking, update_params_with_time)
        }.to have_enqueued_job(BookingReminderJob).twice
        
        # Check reminder times (approximate)
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs.count).to eq(2)
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs.first[:at].to_i).to be_within(1).of((new_start_time - 24.hours).to_i)
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs.second[:at].to_i).to be_within(1).of((new_start_time - 1.hour).to_i)
      end
    end

    context 'when updating time to an unavailable slot' do
       before do
         # Mock availability for the *new* time slot
         allow(staff_member).to receive(:available?).with(new_start_time, new_end_time).and_return(false)
       end

      it 'does not update the booking' do
        original_start_time = existing_booking.start_time
        booking, errors = described_class.update_booking(existing_booking, update_params_with_time)
        expect(booking).to be_nil
        expect(errors).not_to be_nil
        expect(errors[:base]).to include("The selected time is not available for this staff member")
        expect(existing_booking.reload.start_time).to eq(original_start_time)
      end
      
      it 'does not reschedule reminders' do
         expect {
           described_class.update_booking(existing_booking, update_params_with_time)
         }.not_to have_enqueued_job(BookingReminderJob)
      end
    end

    context 'when update parameters are invalid' do
       before do
         # Assume availability check passes if time isn't changing or is valid
         allow(staff_member).to receive(:available?).and_return(true)
       end
       
      it 'does not update the booking and returns validation errors' do
        original_service_id = existing_booking.service_id
        booking, errors = described_class.update_booking(existing_booking, update_params_invalid)
        expect(booking).to be_nil
        expect(errors).not_to be_nil
        expect(errors[:service]).to include("must exist")
        expect(existing_booking.reload.service_id).to eq(original_service_id)
      end
    end
    
    # TODO: Test status change notifications if implemented
  end
  
  describe '.cancel_booking' do
    let!(:booking_to_cancel) { 
      create(:booking, business: tenant, tenant_customer: customer, service: service, 
             staff_member: staff_member, start_time: start_time, end_time: end_time, status: :confirmed)
    }
    let(:cancellation_reason) { "Customer requested cancellation." }

    it 'updates the booking status to cancelled' do
      result = described_class.cancel_booking(booking_to_cancel)
      expect(result).to be true
      expect(booking_to_cancel.reload.status).to eq('cancelled')
    end

    it 'records the cancellation reason if provided' do
      described_class.cancel_booking(booking_to_cancel, cancellation_reason)
      # Uncommented check now that the column exists
      expect(booking_to_cancel.reload.cancellation_reason).to eq(cancellation_reason)
      expect(booking_to_cancel.status).to eq('cancelled') 
    end
    
    # TODO: Add test for customer notification if implemented
    # TODO: Add test for refund processing if implemented (requires payment setup)
    
    it 'succeeds even if the booking is already cancelled' do
      booking_to_cancel.update!(status: :cancelled, cancellation_reason: "Initial reason")
      
      result = described_class.cancel_booking(booking_to_cancel, "Second attempt reason")
      
      expect(result).to be true
      booking_to_cancel.reload
      expect(booking_to_cancel.status).to eq('cancelled')
      # Check if the reason gets updated or stays the same (depends on desired behavior)
      # Assuming it should update:
      expect(booking_to_cancel.cancellation_reason).to eq("Second attempt reason")
    end

    it 'returns false if update fails' do
      # Force an update failure
      allow(booking_to_cancel).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(booking_to_cancel))
      
      result = described_class.cancel_booking(booking_to_cancel, "Reason")
      expect(result).to be false
    end
  end
end 