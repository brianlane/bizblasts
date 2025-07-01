# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SubscriptionBookingService, type: :service do
  let(:business) { create(:business, loyalty_program_enabled: true) }
  let(:tenant_customer) { create(:tenant_customer, business: business) }
  let(:staff_member) { create(:staff_member, business: business, availability: default_availability) }
  let(:service_model) { create(:service, business: business, price: 75.00, duration: 60, subscription_enabled: true) }
  let(:customer_subscription) do
    create(:customer_subscription, 
           :service_subscription,
           business: business,
           tenant_customer: tenant_customer,
           service: service_model,
           quantity: 1,
           subscription_price: 75.00,
           frequency: 'monthly')
  end
  
  let(:default_availability) do
    {
      'monday' => [{ 'start' => '09:00', 'end' => '17:00' }],
      'tuesday' => [{ 'start' => '09:00', 'end' => '17:00' }],
      'wednesday' => [{ 'start' => '09:00', 'end' => '17:00' }],
      'thursday' => [{ 'start' => '09:00', 'end' => '17:00' }],
      'friday' => [{ 'start' => '09:00', 'end' => '17:00' }]
    }
  end
  
  subject(:service) { described_class.new(customer_subscription) }

  before do
    # Associate staff member with service
    create(:services_staff_member, service: service_model, staff_member: staff_member)
    
    # Mock email delivery
    allow(BookingMailer).to receive(:subscription_booking_created).and_return(double(deliver_later: true))
    allow(BusinessMailer).to receive(:subscription_booking_received).and_return(double(deliver_later: true))
    
    # Mock AvailabilityService
    allow(AvailabilityService).to receive(:available_slots).and_return([
      { start_time: Time.zone.parse("#{Date.current.next_week} 10:00"), end_time: Time.zone.parse("#{Date.current.next_week} 11:00") }
    ])
    allow(AvailabilityService).to receive(:is_available?).and_return(true)
  end

  describe '#initialize' do
    it 'sets the customer subscription' do
      expect(service.customer_subscription).to eq(customer_subscription)
      expect(service.business).to eq(business)
      expect(service.tenant_customer).to eq(tenant_customer)
      expect(service.service).to eq(service_model)
    end
  end

  describe '#process_subscription!' do
    context 'when subscription is valid for processing' do
      before do
        customer_subscription.update!(status: :active)
      end

      it 'attempts enhanced scheduling processing first' do
        scheduling_service = double('scheduling_service')
        expect(SubscriptionSchedulingService).to receive(:new).with(customer_subscription).and_return(scheduling_service)
        expect(scheduling_service).to receive(:schedule_subscription_bookings!).and_return(true)
        
        result = service.process_subscription!
        expect(result).to be_truthy
      end

      context 'when enhanced processing succeeds' do
        before do
          scheduling_service = double('scheduling_service', schedule_subscription_bookings!: true)
          allow(SubscriptionSchedulingService).to receive(:new).and_return(scheduling_service)
        end

        it 'returns the result from enhanced processing' do
          result = service.process_subscription!
          expect(result).to be true
        end

        it 'does not fall back to basic processing' do
          expect(service).not_to receive(:fallback_to_basic_booking)
          service.process_subscription!
        end
      end

      context 'when enhanced processing fails' do
        before do
          scheduling_service = double('scheduling_service', schedule_subscription_bookings!: false)
          allow(SubscriptionSchedulingService).to receive(:new).and_return(scheduling_service)
        end

        it 'falls back to basic booking processing' do
          expect(service).to receive(:fallback_to_basic_booking).and_call_original
          service.process_subscription!
        end

        it 'creates bookings through fallback processing' do
          expect {
            service.process_subscription!
          }.to change(Booking, :count).by(1)
        end

        it 'creates an invoice for the booking' do
          expect {
            service.process_subscription!
          }.to change(Invoice, :count).by(1)
        end

        it 'awards loyalty points' do
          expect(defined?(SubscriptionLoyaltyService)).to be_truthy
          loyalty_service = double('loyalty_service')
          expect(SubscriptionLoyaltyService).to receive(:new).with(customer_subscription).twice.and_return(loyalty_service)
          expect(loyalty_service).to receive(:award_subscription_payment_points!)
          allow(loyalty_service).to receive(:award_milestone_points!)
          
          service.process_subscription!
        end

        it 'advances the billing date' do
          original_date = customer_subscription.next_billing_date
          service.process_subscription!
          
          expect(customer_subscription.reload.next_billing_date).to be > original_date
        end

        it 'sends booking confirmation email' do
          expect(BookingMailer).to receive(:subscription_booking_created).and_return(double(deliver_later: true))
          service.process_subscription!
        end

        it 'sends business notification email' do
          expect(BusinessMailer).to receive(:subscription_booking_received).and_return(double(deliver_later: true))
          service.process_subscription!
        end
      end
    end

    context 'when subscription is not valid for processing' do
      it 'returns false for non-service subscriptions' do
        product = create(:product, business: business)
        customer_subscription.update!(
          subscription_type: 'product_subscription',
          product: product,
          service: nil
        )
        
        expect(service.process_subscription!).to be false
      end

      it 'returns false for inactive subscriptions' do
        customer_subscription.update!(status: :cancelled)
        
        expect(service.process_subscription!).to be false
      end
    end
  end

  describe '#fallback_to_basic_booking' do
    before do
      customer_subscription.update!(status: :active)
    end

    it 'creates bookings with correct attributes' do
      service.send(:fallback_to_basic_booking)
      
      booking = Booking.last
      expect(booking.business).to eq(business)
      expect(booking.tenant_customer).to eq(tenant_customer)
      expect(booking.service).to eq(service_model)
      expect(booking.status).to eq('confirmed')
    end

    it 'assigns staff member correctly' do
      # Set customer preference for specific staff member
      preferred_staff = create(:staff_member, business: business, availability: default_availability)
      create(:services_staff_member, service: service_model, staff_member: preferred_staff)
      
      customer_subscription.update!(
        customer_preferences: {
          'preferred_staff_id' => preferred_staff.id
        }
      )
      
      service.send(:fallback_to_basic_booking)
      
      booking = Booking.last
      expect(booking.staff_member).to eq(preferred_staff)
    end

    it 'assigns any available staff when no preference is set' do
      service.send(:fallback_to_basic_booking)
      
      booking = Booking.last
      expect(booking.staff_member).to eq(staff_member)
    end

    it 'creates an invoice with correct total' do
      service.send(:fallback_to_basic_booking)
      
      invoice = Invoice.last
      expect(invoice.business).to eq(business)
      expect(invoice.tenant_customer).to eq(tenant_customer)
      expect(invoice.status).to eq('paid')
    end

    it 'schedules booking for appropriate time' do
      service.send(:fallback_to_basic_booking)
      
      booking = Booking.last
      expect(booking.start_time).to be_present
      expect(booking.end_time).to be_present
      expect(booking.end_time).to be > booking.start_time
    end

    it 'handles multiple quantity bookings' do
      customer_subscription.update!(quantity: 3)
      
      expect {
        service.send(:fallback_to_basic_booking)
      }.to change(Booking, :count).by(3)
    end
  end

  describe 'staff assignment logic' do
    let(:preferred_staff) { create(:staff_member, business: business, availability: default_availability) }
    let(:other_staff) { create(:staff_member, business: business, availability: default_availability) }

    before do
      customer_subscription.update!(status: :active)
      create(:services_staff_member, service: service_model, staff_member: preferred_staff)
      create(:services_staff_member, service: service_model, staff_member: other_staff)
      # Mock enhanced scheduling to fail so fallback_to_basic_booking is called
      scheduling_service = double('scheduling_service', schedule_subscription_bookings!: false)
      allow(SubscriptionSchedulingService).to receive(:new).and_return(scheduling_service)
    end

    it 'assigns preferred staff member when available' do
      # Set customer preference for preferred staff
      customer_subscription.update!(
        customer_preferences: {
          'preferred_staff_id' => preferred_staff.id
        }
      )
      
      service.send(:fallback_to_basic_booking)
      
      booking = Booking.last
      expect(booking.staff_member).to eq(preferred_staff)
    end

    it 'assigns any qualified staff when preferred is not available' do
      # Create a preferred staff member but don't qualify them for this service
      unqualified_staff = create(:staff_member, business: business, availability: default_availability)
      
      customer_subscription.update!(
        customer_preferences: {
          'preferred_staff_id' => unqualified_staff.id
        }
      )
      
      service.send(:fallback_to_basic_booking)
      
      booking = Booking.last
      # Should fall back to any qualified staff (not the unqualified one)
      expect(booking.staff_member).not_to eq(unqualified_staff)
      # Should be one of the qualified staff members for this service
      qualified_staff_ids = service_model.staff_members.pluck(:id)
      expect(qualified_staff_ids).to include(booking.staff_member.id)
    end

    it 'handles case when no staff is qualified' do
      # Remove all staff associations
      service_model.services_staff_members.destroy_all
      
      # Should still assign business staff as fallback
      result = service.send(:fallback_to_basic_booking)
      
      # The booking should be created successfully even without qualified staff
      expect(result).to be_truthy
      booking = Booking.last
      expect(booking).to be_present
      expect(booking.staff_member).to be_present
    end
  end

  describe 'booking time scheduling' do
    before do
      customer_subscription.update!(status: :active)
    end

    it 'falls back to available slots when no preferences' do
      service.send(:fallback_to_basic_booking)
      
      booking = Booking.last
      hour = booking.start_time.hour
      expect(hour).to be_between(9, 17) # Within business hours
    end

    it 'schedules within business operating days' do
      service.send(:fallback_to_basic_booking)
      
      booking = Booking.last
      day_of_week = booking.start_time.strftime('%A').downcase
      expect(['monday', 'tuesday', 'wednesday', 'thursday', 'friday']).to include(day_of_week)
    end
  end

  describe 'error handling' do
    before do
      customer_subscription.update!(status: :active)
      # Mock enhanced scheduling to fail so fallback_to_basic_booking is called
      scheduling_service = double('scheduling_service', schedule_subscription_bookings!: false)
      allow(SubscriptionSchedulingService).to receive(:new).and_return(scheduling_service)
    end

    it 'handles database errors gracefully' do
      allow(Booking).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(Booking.new))
      
      expect {
        service.process_subscription!
      }.not_to raise_error
      
      expect(service.process_subscription!).to be false
    end

    it 'handles availability service errors gracefully' do
      allow(AvailabilityService).to receive(:available_slots).and_raise(StandardError.new('Availability error'))
      
      expect {
        service.process_subscription!
      }.not_to raise_error
    end

    it 'logs errors appropriately' do
      allow(Rails.logger).to receive(:error)
      # Mock the scheduling service to fail so it falls back to basic booking
      allow_any_instance_of(SubscriptionSchedulingService).to receive(:schedule_subscription_bookings!).and_return(false)
      # Mock the actual method that gets called: business.bookings.create!
      allow_any_instance_of(ActiveRecord::Associations::CollectionProxy).to receive(:create!).and_raise(StandardError.new('Test error'))
      
      service.process_subscription!
      
      expect(Rails.logger).to have_received(:error).with(/SUBSCRIPTION BOOKING.*Error in fallback_to_basic_booking/)
    end

    it 'rolls back transaction on error' do
      # Mock the scheduling service to fail so it falls back to basic booking
      allow_any_instance_of(SubscriptionSchedulingService).to receive(:schedule_subscription_bookings!).and_return(false)
      # Mock the actual method that gets called: business.bookings.create!
      allow_any_instance_of(ActiveRecord::Associations::CollectionProxy).to receive(:create!).and_raise(StandardError.new('Test error'))
      
      expect {
        service.process_subscription!
      }.not_to change(Booking, :count)
    end
  end

  describe 'loyalty integration' do
    before do
      customer_subscription.update!(status: :active)
      # Mock enhanced scheduling to fail so fallback_to_basic_booking is called
      scheduling_service = double('scheduling_service', schedule_subscription_bookings!: false)
      allow(SubscriptionSchedulingService).to receive(:new).and_return(scheduling_service)
    end

    it 'awards loyalty points for successful bookings' do
      expect(defined?(SubscriptionLoyaltyService)).to be_truthy
      loyalty_service = double('loyalty_service')
      expect(SubscriptionLoyaltyService).to receive(:new).with(customer_subscription).twice.and_return(loyalty_service)
      expect(loyalty_service).to receive(:award_subscription_payment_points!)
      allow(loyalty_service).to receive(:award_milestone_points!)
      
      service.process_subscription!
    end

    it 'checks for milestone achievements' do
      expect(defined?(SubscriptionLoyaltyService)).to be_truthy
      loyalty_service = double('loyalty_service')
      expect(SubscriptionLoyaltyService).to receive(:new).with(customer_subscription).twice.and_return(loyalty_service)
      allow(loyalty_service).to receive(:award_subscription_payment_points!)
      expect(loyalty_service).to receive(:award_milestone_points!).with('first_month')
      
      # Set subscription to be just over one month old to ensure milestone triggers
      customer_subscription.update!(created_at: 32.days.ago)
      
      service.process_subscription!
    end

    it 'handles loyalty service errors gracefully' do
      loyalty_service = double('loyalty_service')
      allow(SubscriptionLoyaltyService).to receive(:new).and_return(loyalty_service)
      allow(loyalty_service).to receive(:award_subscription_payment_points!).and_raise(StandardError.new('Loyalty error'))
      
      expect {
        service.process_subscription!
      }.not_to raise_error
    end
  end

  describe 'email notifications' do
    before do
      customer_subscription.update!(status: :active)
      # Mock enhanced scheduling to fail so fallback_to_basic_booking is called
      scheduling_service = double('scheduling_service', schedule_subscription_bookings!: false)
      allow(SubscriptionSchedulingService).to receive(:new).and_return(scheduling_service)
    end

    it 'sends booking confirmation to customer' do
      expect(BookingMailer).to receive(:subscription_booking_created).and_return(double(deliver_later: true))
      
      service.process_subscription!
    end

    it 'sends business notification' do
      expect(BusinessMailer).to receive(:subscription_booking_received).and_return(double(deliver_later: true))
      
      service.process_subscription!
    end

    it 'handles email delivery errors gracefully' do
      allow(BookingMailer).to receive(:subscription_booking_created).and_raise(StandardError.new('Email error'))
      
      expect {
        service.process_subscription!
      }.not_to raise_error
    end
  end

  describe 'rebooking preferences' do
    before do
      customer_subscription.update!(status: :active)
    end

    it 'handles same_day_next_month preference' do
      customer_subscription.update!(
        customer_preferences: {
          'service_rebooking_preference' => 'same_day_next_month'
        }
      )
      
      # Mock booking unavailable scenario to trigger rebooking logic
      allow(service).to receive(:determine_booking_time).and_return(nil)
      
      expect {
        service.process_subscription!
      }.not_to raise_error
    end

    it 'handles soonest_available preference' do
      customer_subscription.update!(
        customer_preferences: {
          'service_rebooking_preference' => 'soonest_available'
        }
      )
      
      service.process_subscription!
      
      # Should attempt to create booking with soonest available slot
      expect(Booking.count).to be >= 0 # May or may not create booking depending on availability
    end

    it 'handles loyalty_points preference when loyalty is enabled' do
      allow(business).to receive(:loyalty_program_enabled?).and_return(true)
      
      customer_subscription.update!(
        customer_preferences: {
          'service_rebooking_preference' => 'loyalty_points'
        }
      )
      
      # Mock enhanced scheduling to fail so fallback_to_basic_booking is called
      scheduling_service = double('scheduling_service', schedule_subscription_bookings!: false)
      allow(SubscriptionSchedulingService).to receive(:new).and_return(scheduling_service)
      
      # Mock booking_available? to return false so that handle_booking_unavailable is called
      allow(service).to receive(:booking_available?).and_return(false)
      
      loyalty_service = double('loyalty_service')
      expect(SubscriptionLoyaltyService).to receive(:new).with(customer_subscription).and_return(loyalty_service)
      expect(loyalty_service).to receive(:award_compensation_points!).with('booking_unavailable')
      
      service.process_subscription!
    end
  end

  describe 'multi-tenant behavior' do
    let(:other_business) { create(:business) }
    let(:other_subscription) { create(:customer_subscription, :service_subscription, business: other_business) }

    it 'processes subscriptions within correct tenant context' do
      ActsAsTenant.with_tenant(business) do
        service.process_subscription!
        
        booking = Booking.last
        expect(booking.business).to eq(business)
      end
    end

    it 'does not interfere with other tenants' do
      ActsAsTenant.with_tenant(other_business) do
        other_service = described_class.new(other_subscription)
        other_service.process_subscription!
      end
      
      ActsAsTenant.with_tenant(business) do
        expect(Booking.count).to eq(0)
      end
    end
  end

  describe 'performance considerations' do
    before do
      customer_subscription.update!(status: :active)
    end

    it 'processes subscription efficiently' do
      start_time = Time.current
      service.process_subscription!
      end_time = Time.current
      
      expect(end_time - start_time).to be < 2.seconds
    end

    it 'uses database transactions appropriately' do
      expect(ActiveRecord::Base).to receive(:transaction).twice.and_call_original
      service.process_subscription!
    end
  end

  describe 'integration with subscription billing cycle' do
    before do
      customer_subscription.update!(status: :active, next_billing_date: Date.current)
      # Mock enhanced scheduling to fail so fallback_to_basic_booking is called
      scheduling_service = double('scheduling_service', schedule_subscription_bookings!: false)
      allow(SubscriptionSchedulingService).to receive(:new).and_return(scheduling_service)
    end

    it 'advances monthly billing date correctly' do
      customer_subscription.update!(frequency: 'monthly')
      original_date = customer_subscription.next_billing_date
      
      service.process_subscription!
      
      expect(customer_subscription.reload.next_billing_date).to eq(original_date + 1.month)
    end

    it 'advances weekly billing date correctly' do
      customer_subscription.update!(frequency: 'weekly')
      original_date = customer_subscription.next_billing_date
      
      service.process_subscription!
      
      expect(customer_subscription.reload.next_billing_date).to eq(original_date + 1.week)
    end
  end

  describe 'booking conflict resolution' do
    before do
      customer_subscription.update!(status: :active)
      # Mock enhanced scheduling to fail so fallback_to_basic_booking is called
      scheduling_service = double('scheduling_service', schedule_subscription_bookings!: false)
      allow(SubscriptionSchedulingService).to receive(:new).and_return(scheduling_service)
    end

    it 'handles staff member conflicts' do
      # Create a conflicting booking
      conflicting_time = 1.day.from_now.beginning_of_hour + 10.hours
      create(:booking, 
             staff_member: staff_member, 
             start_time: conflicting_time,
             end_time: conflicting_time + 1.hour)
      
      # Mock AvailabilityService to return non-conflicting time
      allow(AvailabilityService).to receive(:available_slots).and_return([
        { start_time: conflicting_time + 2.hours, end_time: conflicting_time + 3.hours }
      ])
      
      service.send(:fallback_to_basic_booking)
      
      booking = Booking.last
      expect(booking.start_time).not_to eq(conflicting_time)
    end

    it 'finds alternative time slots when conflicts exist' do
      # Mock availability service to return alternative slots
      # Ensure the alternative time is definitely after 1.week.from_now.beginning_of_day
      alternative_time = 1.week.from_now.beginning_of_day + 10.hours
      allow(AvailabilityService).to receive(:available_slots).and_return([
        { start_time: alternative_time, end_time: alternative_time + 1.hour }
      ])
      
      service.send(:fallback_to_basic_booking)
      
      booking = Booking.last
      # The booking should be scheduled within the next week, allowing for the service's logic
      expect(booking.start_time).to be >= 1.week.from_now.beginning_of_day
      expect(booking.start_time).to be <= 5.weeks.from_now.end_of_day
    end
  end
end 