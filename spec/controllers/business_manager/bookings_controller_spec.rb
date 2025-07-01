require 'rails_helper'

RSpec.describe BusinessManager::BookingsController, type: :controller do
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper
  let(:business) { create(:business, hostname: 'testbiz', subdomain: 'testbiz') }
  let(:manager) { create(:user, :manager, business: business) }
  let(:client_user) { create(:user, :client) }
  let(:tenant_customer) { create(:tenant_customer, business: business) }
  let(:service) { create(:service, business: business, duration: 60, price: 100.0) }
  let(:staff_member) { create(:staff_member, business: business) }
  let(:booking_policy) { create(:booking_policy, business: business, cancellation_window_mins: 60, max_daily_bookings: 10) }

  before do
    clear_enqueued_jobs
    ActsAsTenant.current_tenant = business
    @request.host = "#{business.hostname}.lvh.me"
    sign_in manager
    booking_policy # ensure policy exists
  end

  describe 'POST #create' do
    let(:valid_params) do
      {
        booking: {
          service_id: service.id,
          staff_member_id: staff_member.id,
          tenant_customer_id: tenant_customer.id,
          start_time: 1.hour.from_now,
          end_time: 2.hours.from_now,
          notes: 'Manager booking for client'
        }
      }
    end

    it 'allows manager to create a booking for a client user' do
      expect {
        post :create, params: valid_params
      }.to change(Booking, :count).by(1)

      booking = Booking.last
      expect(booking.tenant_customer).to eq(tenant_customer)
      expect(booking.service).to eq(service)
      expect(booking.staff_member).to eq(staff_member)
      expect(booking.status).to eq('pending').or eq('confirmed')
      expect(response).to redirect_to(business_manager_booking_path(booking))
    end
  end

  describe 'PATCH #update (reschedule)' do
    let!(:booking) do
      create(:booking, business: business, service: service, staff_member: staff_member, tenant_customer: tenant_customer, start_time: 1.hour.from_now, end_time: 2.hours.from_now, status: :confirmed)
    end

    let(:new_start_time) { 2.hours.from_now }
    let(:update_params) do
      {
        id: booking.id,
        booking: {
          start_time: new_start_time
        }
      }
    end

    it 'allows manager to reschedule a booking for a client user' do
      patch :update, params: update_params
      expect(response).to redirect_to(business_manager_booking_path(booking))
      booking.reload
      expect(booking.start_time.to_i).to eq(new_start_time.to_i)
    end

    it 'allows manager to reschedule within the cancellation window (override)' do
      travel_to booking.start_time - 30.minutes do
        patch :update, params: update_params
        expect(response).to redirect_to(business_manager_booking_path(booking))
        booking.reload
        expect(booking.start_time.to_i).to eq(new_start_time.to_i)
      end
    end
  end

  describe 'PATCH #cancel (within cancellation window)' do
    let!(:booking) do
      create(:booking, business: business, service: service, staff_member: staff_member, tenant_customer: tenant_customer, start_time: 1.hour.from_now, end_time: 2.hours.from_now, status: :confirmed)
    end

    it 'allows manager to cancel a booking within the cancellation window (override)' do
      travel_to(booking.start_time - 30.minutes) do
        patch :cancel, params: { id: booking.id, cancellation_reason: 'Manager override' }
        booking.reload
        expect(booking.status).to eq('cancelled')
        expect(booking.cancellation_reason).to eq('Manager override')
        expect(response).to redirect_to(business_manager_booking_path(booking))
        expect(flash[:notice]).to match(/cancelled/i)
      end
    end

    it 'enqueues a cancellation email when manager cancels' do
      travel_to booking.start_time - 30.minutes do
        expect {
          patch :cancel, params: { id: booking.id, cancellation_reason: 'Manager override' }
        }.to have_enqueued_mail(BookingMailer, :cancellation).with(booking)
      end
    end
  end

  describe 'PATCH #update_schedule' do
    let!(:booking) do
      create(:booking, business: business, service: service, staff_member: staff_member, tenant_customer: tenant_customer, start_time: 1.hour.from_now, end_time: 2.hours.from_now, status: :confirmed)
    end

    it 'enqueues a status_update email when manager reschedules via update_schedule' do
      new_date = (booking.start_time + 1.day).to_date.to_s
      new_time = (booking.start_time + 1.day).strftime("%H:%M")
      expect {
        patch :update_schedule, params: { id: booking.id, date: new_date, start_time: new_time }
      }.to have_enqueued_mail(BookingMailer, :status_update).with(booking)
    end
  end
end 