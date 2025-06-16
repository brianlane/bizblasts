# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SubscriptionSchedulingService, type: :service do
  let(:business) { create(:business) }
  let(:tenant_customer) { create(:tenant_customer, business: business) }
  let(:service_model) { create(:service, business: business, duration: 60, subscription_enabled: true) }
  let(:staff_member) { create(:staff_member, business: business, availability: default_availability) }
  let(:customer_subscription) do
    create(:customer_subscription,
           :service_subscription,
           business: business,
           tenant_customer: tenant_customer,
           service: service_model,
           frequency: 'monthly',
           quantity: 1)
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

  let(:service_instance) { described_class.new(customer_subscription) }

  before do
    ActsAsTenant.current_tenant = business
    create(:services_staff_member, service: service_model, staff_member: staff_member)
    
    # Mock AvailabilityService
    allow(AvailabilityService).to receive(:available_slots).and_return([
      { start_time: Time.zone.parse("#{Date.current.next_week} 10:00"), end_time: Time.zone.parse("#{Date.current.next_week} 11:00") }
    ])
    allow(AvailabilityService).to receive(:is_available?).and_return(true)
  end

  describe '#initialize' do
    it 'sets up the subscription and service' do
      expect(service_instance.customer_subscription).to eq(customer_subscription)
      expect(service_instance.business).to eq(business)
      expect(service_instance.tenant_customer).to eq(tenant_customer)
      expect(service_instance.service).to eq(service_model)
    end
  end

  describe '#schedule_subscription_bookings!' do
    before do
      customer_subscription.update!(status: :active)
    end

    it 'creates bookings for the subscription period' do
      expect {
        service_instance.schedule_subscription_bookings!
      }.to change(Booking, :count).by(1)
    end

    it 'returns true when bookings are created successfully' do
      result = service_instance.schedule_subscription_bookings!
      expect(result).to be true
    end

    it 'returns false when no bookings can be created' do
      # Mock no available slots
      allow(AvailabilityService).to receive(:available_slots).and_return([])
      
      result = service_instance.schedule_subscription_bookings!
      expect(result).to be false
    end

    it 'creates multiple bookings for quarterly subscriptions' do
      customer_subscription.update!(frequency: 'quarterly')
      
      expect {
        service_instance.schedule_subscription_bookings!
      }.to change(Booking, :count).by(3) # 3 months worth
    end

    it 'handles database errors gracefully' do
      allow(Booking).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(Booking.new))
      
      expect {
        service_instance.schedule_subscription_bookings!
      }.not_to raise_error
      
      expect(service_instance.schedule_subscription_bookings!).to be false
    end

    it 'handles inactive subscriptions gracefully' do
      customer_subscription.update!(status: :cancelled)
      
      result = service_instance.schedule_subscription_bookings!
      expect(result).to be false
    end

    it 'handles invalid subscription types gracefully' do
      product = create(:product, business: business)
      customer_subscription.update!(
        subscription_type: 'product_subscription',
        product: product,
        service: nil
      )
      
      result = service_instance.schedule_subscription_bookings!
      
      expect(result).to be false
    end
  end

  describe '#find_next_available_slot' do
    it 'finds available slot within 8 weeks' do
      result = service_instance.find_next_available_slot
      
      expect(result).to be_present
      expect(result[:date]).to be_present
      expect(result[:time]).to be_present
      expect(result[:staff_member]).to eq(staff_member)
      expect(result[:slot]).to be_present
    end

    it 'respects customer preferred days' do
      # Set customer preference for specific days
      customer_subscription.update!(
        customer_preferences: {
          'preferred_days' => ['monday', 'wednesday', 'friday']
        }
      )
      
      # Mock AvailabilityService to return slots on different days
      monday_time = Time.zone.parse("#{Date.current.next_week.beginning_of_week} 10:00")
      tuesday_time = Time.zone.parse("#{Date.current.next_week.beginning_of_week + 1.day} 10:00")
      
      allow(AvailabilityService).to receive(:available_slots).and_return([
        { start_time: tuesday_time, end_time: tuesday_time + 1.hour }, # Tuesday (not preferred)
        { start_time: monday_time, end_time: monday_time + 1.hour }    # Monday (preferred)
      ])
      
      result = service_instance.find_next_available_slot
      
      # Should choose Monday (preferred day) over Tuesday
      expect(result[:date].strftime('%A').downcase).to eq('monday')
    end

    it 'respects customer preferred times' do
      # Set customer preference for morning times
      customer_subscription.update!(
        customer_preferences: {
          'preferred_time' => 'morning'
        }
      )
      
      # Mock AvailabilityService to return slots at different times
      morning_time = Time.zone.parse("#{Date.current.next_week} 10:00")
      afternoon_time = Time.zone.parse("#{Date.current.next_week} 15:00")
      
      allow(AvailabilityService).to receive(:available_slots).and_return([
        { start_time: afternoon_time, end_time: afternoon_time + 1.hour }, # Afternoon
        { start_time: morning_time, end_time: morning_time + 1.hour }       # Morning (preferred)
      ])
      
      result = service_instance.find_next_available_slot
      
      # Should choose morning time
      expect(result[:time].hour).to be < 12
    end

    it 'returns nil when no slots are available' do
      allow(AvailabilityService).to receive(:available_slots).and_return([])
      
      result = service_instance.find_next_available_slot
      
      expect(result).to be_nil
    end

    it 'accepts preferred date parameter' do
      preferred_date = 2.weeks.from_now.to_date
      
      result = service_instance.find_next_available_slot(preferred_date)
      
      expect(result[:date]).to be >= preferred_date
    end
  end

  describe '#reschedule_booking' do
    let(:booking) { create(:booking, business: business, tenant_customer: tenant_customer, service: service_model, staff_member: staff_member) }

    it 'reschedules booking to next available slot' do
      original_time = booking.start_time
      
      # Mock different available time
      allow(AvailabilityService).to receive(:available_slots).and_return([
        { start_time: Time.zone.parse("#{Date.current.next_week} 15:00"), end_time: Time.zone.parse("#{Date.current.next_week} 16:00") }
      ])
      
      result = service_instance.reschedule_booking(booking)
      
      expect(result).to be true
      expect(booking.reload.start_time).not_to eq(original_time)
    end

    it 'returns false for bookings not belonging to subscription' do
      other_booking = create(:booking, business: business)
      
      result = service_instance.reschedule_booking(other_booking)
      
      expect(result).to be false
    end

    it 'returns false when no alternative slots available' do
      allow(AvailabilityService).to receive(:available_slots).and_return([])
      
      result = service_instance.reschedule_booking(booking)
      
      expect(result).to be false
    end

    it 'handles database errors gracefully' do
      allow(booking).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(booking))
      
      result = service_instance.reschedule_booking(booking)
      
      expect(result).to be false
    end
  end

  describe '#check_upcoming_bookings' do
    let!(:valid_booking) { create(:booking, business: business, tenant_customer: tenant_customer, service: service_model, staff_member: staff_member, start_time: 1.week.from_now) }
    let!(:invalid_booking) { create(:booking, business: business, tenant_customer: tenant_customer, service: service_model, staff_member: staff_member, start_time: 1.week.from_now + 1.hour) }

    before do
      # Make one booking invalid by making staff unavailable
      allow(AvailabilityService).to receive(:is_available?).with(
        staff_member: staff_member,
        start_time: invalid_booking.start_time,
        end_time: invalid_booking.end_time,
        service: service_model,
        exclude_booking_id: invalid_booking.id
      ).and_return(false)
      
      allow(AvailabilityService).to receive(:is_available?).with(
        staff_member: staff_member,
        start_time: valid_booking.start_time,
        end_time: valid_booking.end_time,
        service: service_model,
        exclude_booking_id: valid_booking.id
      ).and_return(true)
    end

    it 'checks upcoming bookings within 2 weeks' do
      expect(service_instance).to receive(:reschedule_booking).with(invalid_booking)
      
      service_instance.check_upcoming_bookings
    end

    it 'does not reschedule valid bookings' do
      expect(service_instance).not_to receive(:reschedule_booking).with(valid_booking)
      
      service_instance.check_upcoming_bookings
    end
  end

  describe 'private methods' do
    describe '#calculate_bookings_for_period' do
      it 'returns 1 for weekly frequency' do
        customer_subscription.update!(frequency: 'weekly')
        
        result = service_instance.send(:calculate_bookings_for_period)
        
        expect(result).to eq(1)
      end

      it 'returns 3 for quarterly frequency' do
        customer_subscription.update!(frequency: 'quarterly')
        
        result = service_instance.send(:calculate_bookings_for_period)
        
        expect(result).to eq(3)
      end

      it 'respects quantity setting' do
        customer_subscription.update!(frequency: 'monthly', quantity: 2)
        
        result = service_instance.send(:calculate_bookings_for_period)
        
        expect(result).to eq(2)
      end
    end

    describe '#date_matches_preferences?' do
      it 'returns true when no preferred days specified' do
        # No customer preferences set
        customer_subscription.update!(customer_preferences: nil)
        
        monday = Date.current.next_week.beginning_of_week
        result = service_instance.send(:date_matches_preferences?, monday)
        
        expect(result).to be true
      end

      it 'returns true when date matches preferred days' do
        # Set customer preference for Monday and Friday
        customer_subscription.update!(
          customer_preferences: {
            'preferred_days' => ['monday', 'friday']
          }
        )
        
        monday = Date.current.next_week.beginning_of_week
        result = service_instance.send(:date_matches_preferences?, monday)
        
        expect(result).to be true
      end

      it 'returns false when date does not match preferred days' do
        # Set customer preference for Monday and Friday only
        customer_subscription.update!(
          customer_preferences: {
            'preferred_days' => ['monday', 'friday']
          }
        )
        
        tuesday = Date.current.next_week.beginning_of_week + 1.day
        result = service_instance.send(:date_matches_preferences?, tuesday)
        
        expect(result).to be false
      end
    end

    describe '#booking_still_valid?' do
      let(:booking) { create(:booking, business: business, staff_member: staff_member, service: service_model) }

      it 'returns true for valid bookings' do
        result = service_instance.send(:booking_still_valid?, booking)
        
        expect(result).to be true
      end

      it 'returns false when staff is inactive' do
        staff_member.update!(active: false)
        
        result = service_instance.send(:booking_still_valid?, booking)
        
        expect(result).to be false
      end

      it 'returns false when staff cannot perform service' do
        booking.service.services_staff_members.destroy_all
        
        result = service_instance.send(:booking_still_valid?, booking)
        
        expect(result).to be false
      end

      it 'returns false when staff is not available' do
        allow(AvailabilityService).to receive(:is_available?).and_return(false)
        
        result = service_instance.send(:booking_still_valid?, booking)
        
        expect(result).to be false
      end
    end
  end

  describe 'error handling' do
    it 'handles invalid subscription types gracefully' do
      product = create(:product, business: business)
      customer_subscription.update!(
        subscription_type: 'product_subscription',
        product: product,
        service: nil
      )
      
      result = service_instance.schedule_subscription_bookings!
      
      expect(result).to be false
    end

    it 'handles inactive subscriptions gracefully' do
      customer_subscription.update!(status: :cancelled)
      
      result = service_instance.schedule_subscription_bookings!
      
      expect(result).to be false
    end

    it 'logs errors appropriately' do
      allow(Rails.logger).to receive(:error)
      # Mock the actual method that gets called: business.bookings.create!
      allow_any_instance_of(ActiveRecord::Associations::CollectionProxy).to receive(:create!).and_raise(StandardError.new('Test error'))
      
      service_instance.schedule_subscription_bookings!
      
      expect(Rails.logger).to have_received(:error).with(/SUBSCRIPTION SCHEDULING.*Error creating booking/)
    end
  end

  describe 'multi-tenant behavior' do
    let(:other_business) { create(:business) }
    let(:other_subscription) { create(:customer_subscription, :service_subscription, business: other_business) }

    it 'isolates scheduling by business' do
      ActsAsTenant.with_tenant(business) do
        service_instance.schedule_subscription_bookings!
        
        booking = Booking.last
        expect(booking.business).to eq(business)
      end
    end

    it 'does not access other business data' do
      ActsAsTenant.with_tenant(other_business) do
        other_service = described_class.new(other_subscription)
        
        expect {
          other_service.find_next_available_slot
        }.not_to raise_error
      end
    end
  end

  describe 'performance and optimization' do
    it 'performs scheduling operations efficiently' do
      start_time = Time.current
      service_instance.schedule_subscription_bookings!
      end_time = Time.current
      
      expect(end_time - start_time).to be < 2.seconds
    end

    it 'uses database transactions appropriately' do
      expect(ActiveRecord::Base).to receive(:transaction).exactly(2).times.and_call_original
      service_instance.schedule_subscription_bookings!
    end
  end
end 