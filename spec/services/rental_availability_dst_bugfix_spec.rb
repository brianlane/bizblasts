# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'DST Bug Fix: Consistent end-time calculation', type: :service do
  let(:business) { create(:business, time_zone: 'America/New_York') }

  let(:rental_product) do
    create(:product, :rental,
      business: business,
      rental_quantity_available: 5,
      allow_daily_rental: true,
      min_rental_duration_mins: 60,
      max_rental_duration_mins: 10 * 24 * 60,
      rental_availability_schedule: {
        monday: [{ start: '09:00', end: '17:00' }],
        tuesday: [{ start: '09:00', end: '17:00' }],
        wednesday: [{ start: '09:00', end: '17:00' }],
        thursday: [{ start: '09:00', end: '17:00' }],
        friday: [{ start: '09:00', end: '17:00' }],
        saturday: [{ start: '09:00', end: '17:00' }],
        sunday: [{ start: '09:00', end: '17:00' }]
      }
    )
  end

  describe 'Cursor Bug: Inconsistent end-time between slots and bookings' do
    context 'during DST spring forward (March 8, 2026)' do
      it 'uses consistent fixed-minute durations for slot display and booking' do
        # March 7, 2026 is the Friday before DST spring-forward on March 8
        date = Date.parse('2026-03-07')
        duration_mins = 1440 # 1 day = 1440 minutes

        Time.use_zone(business.time_zone) do
          travel_to Time.zone.parse('2026-03-07 00:00:00') do
            # Generate available slots
            slots = RentalAvailabilityService.available_slots(
              rental: rental_product,
              date: date,
              duration_mins: duration_mins,
              quantity: 1
            )

            expect(slots).not_to be_empty
            slot = slots.first

            # Slot end time uses fixed minutes
            start_time = date.in_time_zone.change(hour: 9, min: 0)
            expected_end_time = start_time + duration_mins.minutes

            expect(slot[:start_time]).to eq(start_time)
            expect(slot[:end_time]).to eq(expected_end_time)

            # Create a booking using the same parameters
            customer = create(:tenant_customer, business: business)
            service = RentalBookingService.new(
              rental: rental_product,
              tenant_customer: customer,
              params: {
                start_time: start_time,
                duration_mins: duration_mins,
                quantity: 1
              }
            )

            result = service.create_booking
            expect(result[:success]).to be true

            booking = result[:booking]
            # Booking should use the exact same end_time as the slot
            expect(booking.start_time).to eq(slot[:start_time])
            expect(booking.end_time).to eq(slot[:end_time])

            # Verify the end times match (no 1-hour discrepancy)
            expect(booking.end_time).to eq(expected_end_time)
          end
        end
      end
    end
  end

  describe 'Codex Bug: Preserve fixed-minute durations across DST' do
    context 'during DST spring forward' do
      it 'maintains exact 1440-minute duration despite DST clock change' do
        # March 7, 2026 at 10am -> crosses DST on March 8 at 2am
        Time.use_zone(business.time_zone) do
          start_time = Time.zone.parse('2026-03-07 10:00:00')
          duration_mins = 1440 # Exactly 1 day

          # Calculate end_time using fixed minutes (the correct way)
          end_time = start_time + duration_mins.minutes

          # Verify the duration is exactly 1440 minutes
          actual_duration_mins = ((end_time - start_time) / 60).to_i
          expect(actual_duration_mins).to eq(1440)

          # During spring-forward DST, clock jumps from 2am to 3am
          # So 10am + 1440 mins = 11am next day (not 10am)
          expect(end_time.hour).to eq(11) # Not 10!
          expect(end_time.day).to eq(8)

          # Pricing calculation uses elapsed minutes
          pricing = rental_product.calculate_rental_price(start_time, end_time)
          expect(pricing).not_to be_nil
          expect(pricing[:quantity]).to eq(1) # 1 day, not 2 days

          # Duration validation uses elapsed minutes
          is_valid = rental_product.valid_rental_duration?(start_time, end_time)
          expect(is_valid).to be true

          # If max duration is exactly 1440 mins, it should still pass
          rental_product.update!(max_rental_duration_mins: 1440)
          is_valid = rental_product.valid_rental_duration?(start_time, end_time)
          expect(is_valid).to be true # Should not be rejected as 25 hours / 2 days
        end
      end
    end

    context 'during DST fall back' do
      it 'maintains exact 1440-minute duration despite DST clock change' do
        # November 1, 2026 at 10am -> crosses DST fallback on Nov 1 at 2am
        Time.use_zone(business.time_zone) do
          # Fall back happened earlier that same day, so let's test Oct 31 -> Nov 1
          start_time = Time.zone.parse('2026-10-31 10:00:00')
          duration_mins = 1440

          end_time = start_time + duration_mins.minutes

          # Verify exact duration
          actual_duration_mins = ((end_time - start_time) / 60).to_i
          expect(actual_duration_mins).to eq(1440)

          # During fall-back DST, clock repeats 1am-2am
          # So 10am + 1440 mins = 9am next day (not 10am)
          expect(end_time.hour).to eq(9) # Not 10!
          expect(end_time.day).to eq(1)

          # Pricing should still recognize this as 1 day
          pricing = rental_product.calculate_rental_price(start_time, end_time)
          expect(pricing).not_to be_nil
          expect(pricing[:quantity]).to eq(1) # 1 day, not 2 days

          # Duration validation should pass
          rental_product.update!(max_rental_duration_mins: 1440)
          is_valid = rental_product.valid_rental_duration?(start_time, end_time)
          expect(is_valid).to be true
        end
      end
    end
  end
end
