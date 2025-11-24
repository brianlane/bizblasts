require 'rails_helper'
require 'active_support/testing/time_helpers'

RSpec.describe Booking, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:business) { create(:business) }
  let(:service) { create(:service, business: business) }
  let(:staff_member) { create(:staff_member, business: business) }
  let(:customer) { create(:tenant_customer, business: business) }
  
  describe "associations" do
    it 'belongs to business (optional for orphaned bookings)' do
      expect(Booking.reflect_on_association(:business)).to be_present
      expect(Booking.reflect_on_association(:business).options[:optional]).to be true
    end

    it 'belongs to service (optional for orphaned bookings)' do
      expect(Booking.reflect_on_association(:service)).to be_present
      expect(Booking.reflect_on_association(:service).options[:optional]).to be true
    end

    it 'belongs to staff_member (optional for orphaned bookings)' do
      expect(Booking.reflect_on_association(:staff_member)).to be_present
      expect(Booking.reflect_on_association(:staff_member).options[:optional]).to be true
    end

    it 'belongs to tenant_customer (optional for orphaned bookings)' do
      expect(Booking.reflect_on_association(:tenant_customer)).to be_present
      expect(Booking.reflect_on_association(:tenant_customer).options[:optional]).to be true
    end

    it { should belong_to(:promotion).optional }
    it { should have_one(:invoice) }
    it { should belong_to(:service_variant).optional }
  end
  
  describe "validations" do
    it { should validate_presence_of(:service) }
    it { should validate_presence_of(:tenant_customer) }
    it { should validate_presence_of(:staff_member) }
    it { should validate_presence_of(:start_time) }
    it { should validate_presence_of(:end_time) }
    it { should validate_presence_of(:status) }
  end
  
  describe "booking status" do
    let(:booking) { build(:booking, business: business, service: service, 
                         staff_member: staff_member, tenant_customer: customer) }
    
    it "defaults to pending status" do
      expect(booking.status).to eq("pending")
    end
    
    it "can be marked as confirmed" do
      booking.status = :confirmed
      expect(booking).to be_valid
      expect(booking.status).to eq("confirmed")
    end
    
    it "can be marked as cancelled" do
      booking.status = :cancelled
      expect(booking).to be_valid
      expect(booking.status).to eq("cancelled")
    end
    
    it "can be cancelled with a reason" do
      booking.save!
      booking.cancel!("Customer requested")
      expect(booking.status).to eq("cancelled")
      expect(booking.cancellation_reason).to eq("Customer requested")
    end
    
    it "checks if booking can be cancelled" do
      booking.start_time = 1.day.from_now
      booking.end_time = booking.start_time + 1.hour
      booking.save!
      
      expect(booking.can_cancel?).to be true
      
      booking.status = :cancelled
      expect(booking.can_cancel?).to be false
      
      booking.status = :pending
      booking.start_time = 1.day.ago
      booking.end_time = booking.start_time + 1.hour
      expect(booking.can_cancel?).to be false
    end
  end
  
  describe "booking scopes" do
    around(:each) do |example|
      travel_to Time.zone.local(2000, 1, 1, 12) do
        example.run
      end
    end

    before do
      # Create some bookings for testing scopes
      @past_booking = create(:booking, business: business, service: service, 
                            staff_member: staff_member, tenant_customer: customer,
                            start_time: Time.current - 2.days, end_time: Time.current - 2.days + 1.hour,
                            status: :completed)
                            
      @today_booking = create(:booking, business: business, service: service, 
                            staff_member: staff_member, tenant_customer: customer,
                            start_time: Time.current + 2.hours, end_time: Time.current + 3.hours,
                            status: :confirmed)
                            
      @future_booking = create(:booking, business: business, service: service, 
                            staff_member: staff_member, tenant_customer: customer,
                            start_time: Time.current + 2.days, end_time: Time.current + 2.days + 1.hour,
                            status: :pending)
                            
      @cancelled_booking = create(:booking, business: business, service: service, 
                                staff_member: staff_member, tenant_customer: customer,
                                start_time: Time.current + 3.days, end_time: Time.current + 3.days + 1.hour,
                                status: :cancelled)
    end
    
    it "filters upcoming bookings" do
      upcoming = Booking.upcoming
      expect(upcoming).to include(@today_booking, @future_booking)
      expect(upcoming).not_to include(@past_booking, @cancelled_booking)
    end
    
    it "filters past bookings" do
      past = Booking.past
      expect(past).to include(@past_booking)
      expect(past).not_to include(@today_booking, @future_booking, @cancelled_booking)
    end
    
    it "filters bookings for today" do
      today = Booking.today
      expect(today).to include(@today_booking)
      expect(today).not_to include(@past_booking, @future_booking, @cancelled_booking)
    end
    
    it "filters bookings for a specific date" do
      future_date = 2.days.from_now.to_date
      on_date = Booking.on_date(future_date)
      expect(on_date).to include(@future_booking)
      expect(on_date).not_to include(@past_booking, @today_booking, @cancelled_booking)
    end
    
    it "filters bookings by staff" do
      staff_bookings = Booking.for_staff(staff_member.id)
      expect(staff_bookings).to include(@past_booking, @today_booking, @future_booking, @cancelled_booking)
    end
    
    it "filters bookings by customer" do
      customer_bookings = Booking.for_customer(customer.id)
      expect(customer_bookings).to include(@past_booking, @today_booking, @future_booking, @cancelled_booking)
    end
  end
  
  describe "booking validations" do
    let(:booking) { build(:booking, business: business, service: service, 
                         staff_member: staff_member, tenant_customer: customer,
                         start_time: Time.current + 1.hour, end_time: Time.current + 2.hours) }
    
    it "calculates duration correctly" do
      expect(booking.duration).to eq(60)
    end
    
    it "validates end time is after start time" do
      booking.end_time = booking.start_time - 30.minutes
      expect(booking).not_to be_valid
      expect(booking.errors[:end_time]).to include("must be after the start time")
    end
    
    it "validates non-overlapping bookings" do
      booking.save!
      
      overlapping_booking = build(:booking, business: business, service: service, 
                                staff_member: staff_member, tenant_customer: customer,
                                start_time: booking.start_time + 30.minutes, 
                                end_time: booking.end_time + 30.minutes)
                                
      expect(overlapping_booking).not_to be_valid
      expect(overlapping_booking.errors[:base]).to include("Booking conflicts with another existing booking for this staff member, considering buffer time")
    end
    
    context "minimum duration validation" do
      let!(:policy) { create(:booking_policy, business: business, min_duration_mins: 45) }
      
      it "is invalid when booking duration is less than minimum" do
        booking = build(:booking, 
                       business: business, 
                       service: service,
                       staff_member: staff_member,
                       tenant_customer: customer,
                       start_time: Time.zone.now + 1.day,
                       end_time: Time.zone.now + 1.day + 30.minutes)
        
        expect(booking).not_to be_valid
        expect(booking.errors[:base]).to include("Booking duration (30 minutes) cannot be less than the minimum required duration (45 minutes)")
      end
      
      it "is valid when booking duration equals minimum" do
        booking = build(:booking, 
                       business: business, 
                       service: service,
                       staff_member: staff_member,
                       tenant_customer: customer,
                       start_time: Time.zone.now + 1.day,
                       end_time: Time.zone.now + 1.day + 45.minutes)
        
        # Only checking the min_duration validation, not other validations
        booking.valid?
        expect(booking.errors[:base]).not_to include(/minimum required duration/)
      end
      
      it "is valid when booking duration exceeds minimum" do
        booking = build(:booking, 
                       business: business, 
                       service: service,
                       staff_member: staff_member,
                       tenant_customer: customer,
                       start_time: Time.zone.now + 1.day,
                       end_time: Time.zone.now + 1.day + 60.minutes)
        
        # Only checking the min_duration validation, not other validations
        booking.valid?
        expect(booking.errors[:base]).not_to include(/minimum required duration/)
      end
    end
    
    context "maximum duration validation" do
      let!(:policy) { create(:booking_policy, business: business, max_duration_mins: 120) }
      
      it "is invalid when booking duration exceeds maximum" do
        booking = build(:booking, 
                       business: business, 
                       service: service,
                       staff_member: staff_member,
                       tenant_customer: customer,
                       start_time: Time.zone.now + 1.day,
                       end_time: Time.zone.now + 1.day + 150.minutes)
        
        expect(booking).not_to be_valid
        expect(booking.errors[:base]).to include("Booking duration (150 minutes) cannot exceed the maximum allowed duration (120 minutes)")
      end
      
      it "is valid when booking duration equals maximum" do
        booking = build(:booking, 
                       business: business, 
                       service: service,
                       staff_member: staff_member,
                       tenant_customer: customer,
                       start_time: Time.zone.now + 1.day,
                       end_time: Time.zone.now + 1.day + 120.minutes)
        
        # Only checking the max_duration validation, not other validations
        booking.valid?
        expect(booking.errors[:base]).not_to include(/maximum allowed duration/)
      end
      
      it "is valid when booking duration is less than maximum" do
        booking = build(:booking, 
                       business: business, 
                       service: service,
                       staff_member: staff_member,
                       tenant_customer: customer,
                       start_time: Time.zone.now + 1.day,
                       end_time: Time.zone.now + 1.day + 90.minutes)
        
        # Only checking the max_duration validation, not other validations
        booking.valid?
        expect(booking.errors[:base]).not_to include(/maximum allowed duration/)
      end
    end
  end

  describe 'quantity validations' do
    let(:service_exp) { create(:service, business: business, service_type: :experience, min_bookings: 2, max_bookings: 5) }
    let(:service_std) { create(:service, business: business, service_type: :standard) }

    context 'for experience services' do
      it 'is invalid when quantity is less than min_bookings' do
        booking = build(:booking, business: business, service: service_exp, staff_member: staff_member, tenant_customer: customer, start_time: Time.current + 1.hour, end_time: Time.current + 2.hours, quantity: 1)
        expect(booking).not_to be_valid
        expect(booking.errors[:quantity]).to include("must be greater than or equal to #{service_exp.min_bookings}")
      end

      it 'is invalid when quantity is greater than max_bookings' do
        booking = build(:booking, business: business, service: service_exp, staff_member: staff_member, tenant_customer: customer, start_time: Time.current + 1.hour, end_time: Time.current + 2.hours, quantity: service_exp.max_bookings + 1)
        expect(booking).not_to be_valid
        expect(booking.errors[:quantity]).to include("must be less than or equal to #{service_exp.max_bookings}")
      end

      it 'is valid when quantity is within range' do
        booking = build(:booking, business: business, service: service_exp, staff_member: staff_member, tenant_customer: customer, start_time: Time.current + 1.hour, end_time: Time.current + 2.hours, quantity: 3)
        expect(booking).to be_valid
      end
    end

    context 'for standard services' do
      it 'allows any quantity >= 1' do
        booking = build(:booking, business: business, service: service_std, staff_member: staff_member, tenant_customer: customer, start_time: Time.current + 1.hour, end_time: Time.current + 2.hours, quantity: 5)
        expect(booking).to be_valid
      end
    end
  end

  describe 'event booking validations' do
    let(:event_business) { create(:business, time_zone: 'America/New_York') }
    let(:event_service) { create(:service, :event, business: event_business, event_starts_at: 1.week.from_now.in_time_zone('America/New_York').change(sec: 0, usec: 0)) }
    let(:event_staff) { create(:staff_member, business: event_business) }
    let(:event_customer) { create(:tenant_customer, business: event_business) }

    context 'booking date and time validation' do
      it 'is valid when booking matches the event date and time' do
        event_start = event_service.event_starts_at
        event_end = event_start + event_service.duration.minutes
        booking = build(:booking,
                       business: event_business,
                       service: event_service,
                       staff_member: event_staff,
                       tenant_customer: event_customer,
                       start_time: event_start,
                       end_time: event_end,
                       quantity: 5)
        expect(booking).to be_valid
      end

      it 'is invalid when booking date does not match event date' do
        wrong_date = event_service.event_starts_at + 1.day
        wrong_end = wrong_date + event_service.duration.minutes
        booking = build(:booking,
                       business: event_business,
                       service: event_service,
                       staff_member: event_staff,
                       tenant_customer: event_customer,
                       start_time: wrong_date,
                       end_time: wrong_end,
                       quantity: 5)
        expect(booking).not_to be_valid
        expect(booking.errors[:start_time]).to include(a_string_matching(/must match the scheduled event time/))
      end

      it 'is invalid when booking time does not match event time' do
        wrong_time = event_service.event_starts_at.change(hour: (event_service.event_starts_at.hour + 2) % 24)
        wrong_end = wrong_time + event_service.duration.minutes
        booking = build(:booking,
                       business: event_business,
                       service: event_service,
                       staff_member: event_staff,
                       tenant_customer: event_customer,
                       start_time: wrong_time,
                       end_time: wrong_end,
                       quantity: 5)
        expect(booking).not_to be_valid
        expect(booking.errors[:start_time]).to include(a_string_matching(/must match the scheduled event time/))
      end
    end

    context 'past event validation' do
      let(:past_event_service) { create(:service, :event, business: event_business, event_starts_at: 1.day.ago.in_time_zone('America/New_York').change(sec: 0, usec: 0)) }

      it 'is invalid when event is in the past' do
        event_start = past_event_service.event_starts_at
        event_end = event_start + past_event_service.duration.minutes
        booking = build(:booking,
                       business: event_business,
                       service: past_event_service,
                       staff_member: event_staff,
                       tenant_customer: event_customer,
                       start_time: event_start,
                       end_time: event_end,
                       quantity: 5)
        expect(booking).not_to be_valid
        expect(booking.errors[:base]).to include(a_string_matching(/has already passed/))
      end
    end

    context 'timezone handling' do
      let(:pst_business) { create(:business, time_zone: 'America/Los_Angeles', state: 'CA') }
      let(:pst_event) { create(:service, :event, business: pst_business, event_starts_at: 1.week.from_now.in_time_zone('America/Los_Angeles').change(hour: 14, min: 0, sec: 0, usec: 0)) }
      let(:pst_staff) { create(:staff_member, business: pst_business) }
      let(:pst_customer) { create(:tenant_customer, business: pst_business) }

      it 'correctly validates bookings across different timezones' do
        event_start = pst_event.event_starts_at
        event_end = event_start + pst_event.duration.minutes
        booking = build(:booking,
                       business: pst_business,
                       service: pst_event,
                       staff_member: pst_staff,
                       tenant_customer: pst_customer,
                       start_time: event_start,
                       end_time: event_end,
                       quantity: 3)
        expect(booking).to be_valid
      end

      it 'rejects bookings with wrong timezone-converted times' do
        # Try to book at a time that looks correct in UTC but wrong in PST
        wrong_time = pst_event.event_starts_at.utc + 1.hour
        wrong_end = wrong_time + pst_event.duration.minutes
        booking = build(:booking,
                       business: pst_business,
                       service: pst_event,
                       staff_member: pst_staff,
                       tenant_customer: pst_customer,
                       start_time: wrong_time,
                       end_time: wrong_end,
                       quantity: 3)
        expect(booking).not_to be_valid
      end
    end

    context 'capacity management' do
      it 'respects min and max bookings for events' do
        event_start = event_service.event_starts_at
        event_end = event_start + event_service.duration.minutes

        # Min bookings validation
        booking_too_few = build(:booking,
                                business: event_business,
                                service: event_service,
                                staff_member: event_staff,
                                tenant_customer: event_customer,
                                start_time: event_start,
                                end_time: event_end,
                                quantity: event_service.min_bookings - 1)
        expect(booking_too_few).not_to be_valid
        expect(booking_too_few.errors[:quantity]).to be_present

        # Max bookings validation
        booking_too_many = build(:booking,
                                 business: event_business,
                                 service: event_service,
                                 staff_member: event_staff,
                                 tenant_customer: event_customer,
                                 start_time: event_start,
                                 end_time: event_end,
                                 quantity: event_service.max_bookings + 1)
        expect(booking_too_many).not_to be_valid
        expect(booking_too_many.errors[:quantity]).to be_present
      end
    end
  end
end
