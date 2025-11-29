# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RentalAvailabilityService, 'multi-day rental slot generation', type: :service do
  let(:business) { create(:business, time_zone: 'America/New_York') }

  let(:rental_product) do
    create(:product, :rental,
      business: business,
      rental_quantity_available: 5,
      allow_hourly_rental: true,
      allow_daily_rental: true,
      allow_weekly_rental: true,
      min_rental_duration_mins: 60,
      max_rental_duration_mins: 7 * 24 * 60,
      rental_availability_schedule: availability_schedule
    )
  end

  # Schedule with 9am-5pm availability Monday-Friday
  let(:availability_schedule) do
    {
      monday: [{ start: '09:00', end: '17:00' }],
      tuesday: [{ start: '09:00', end: '17:00' }],
      wednesday: [{ start: '09:00', end: '17:00' }],
      thursday: [{ start: '09:00', end: '17:00' }],
      friday: [{ start: '09:00', end: '17:00' }],
      saturday: [],
      sunday: []
    }
  end

  describe '.available_slots' do
    # Get next Monday from today to ensure tests work regardless of current date
    let(:next_monday) { Date.current + ((1 - Date.current.wday) % 7 + 7) }

    context 'Bug Fix: Single-day rental slot generation' do
      it 'generates slots for 2-hour rental within 9am-5pm window' do
        date = next_monday
        duration_mins = 120 # 2 hours
        quantity = 1

        slots = described_class.available_slots(
          rental: rental_product,
          date: date,
          duration_mins: duration_mins,
          quantity: quantity
        )

        expect(slots).not_to be_empty
        # Should have slots from 9am to 3pm (last slot is 3pm-5pm)
        first_slot = slots.first
        last_slot = slots.last

        Time.use_zone(business.time_zone) do
          expect(first_slot[:start_time]).to eq(date.in_time_zone.change(hour: 9, min: 0))
          expect(last_slot[:start_time]).to eq(date.in_time_zone.change(hour: 15, min: 0))
        end
      end

      it 'does not generate slots when 2-hour rental cannot fit in window' do
        # Update schedule to have only 1-hour window
        rental_product.update!(
          rental_availability_schedule: {
            monday: [{ start: '09:00', end: '10:00' }]
          }
        )

        date = next_monday
        duration_mins = 120 # 2 hours (cannot fit in 1-hour window)
        quantity = 1

        slots = described_class.available_slots(
          rental: rental_product,
          date: date,
          duration_mins: duration_mins,
          quantity: quantity
        )

        expect(slots).to be_empty
      end
    end

    context 'Bug Fix: Multi-day rental slot generation' do
      it 'generates slots for 2-day rental (pickup times throughout the day)' do
        date = next_monday
        duration_mins = 2 * 24 * 60 # 2 days = 2880 minutes
        quantity = 1

        slots = described_class.available_slots(
          rental: rental_product,
          date: date,
          duration_mins: duration_mins,
          quantity: quantity
        )

        # Before fix: slots would be empty because end_boundary would be:
        # 5pm - 2880 minutes = way before 9am, so no slots generated
        # After fix: end_boundary = period[:end] for multi-day, so slots generated
        expect(slots).not_to be_empty

        Time.use_zone(business.time_zone) do
          # Should have slots from 9am to 5pm on Monday (pickup times)
          first_slot = slots.first
          last_slot = slots.last

          # First pickup slot at 9am Monday, ends Wednesday 9am
          expect(first_slot[:start_time]).to eq(date.in_time_zone.change(hour: 9, min: 0))
          expect(first_slot[:end_time]).to eq((date + 2.days).in_time_zone.change(hour: 9, min: 0))

          # Last pickup slot at 5pm Monday, ends Wednesday 5pm
          expect(last_slot[:start_time]).to eq(date.in_time_zone.change(hour: 17, min: 0))
          expect(last_slot[:end_time]).to eq((date + 2.days).in_time_zone.change(hour: 17, min: 0))
        end
      end

      it 'generates slots for 7-day weekly rental' do
        date = next_monday
        duration_mins = 7 * 24 * 60 # 1 week = 10080 minutes
        quantity = 1

        slots = described_class.available_slots(
          rental: rental_product,
          date: date,
          duration_mins: duration_mins,
          quantity: quantity
        )

        # Should generate pickup time slots throughout Monday 9am-5pm
        expect(slots).not_to be_empty

        Time.use_zone(business.time_zone) do
          first_slot = slots.first
          last_slot = slots.last

          # First pickup at 9am Monday, return next Monday 9am
          expect(first_slot[:start_time]).to eq(date.in_time_zone.change(hour: 9, min: 0))
          expect(first_slot[:end_time]).to eq((date + 7.days).in_time_zone.change(hour: 9, min: 0))

          # Last pickup at 5pm Monday, return next Monday 5pm
          expect(last_slot[:start_time]).to eq(date.in_time_zone.change(hour: 17, min: 0))
          expect(last_slot[:end_time]).to eq((date + 7.days).in_time_zone.change(hour: 17, min: 0))
        end
      end

      it 'respects availability validation for multi-day rentals' do
        # Get next Friday (Friday + weekend = no availability on Sat/Sun)
        next_friday = next_monday - 3.days
        date = next_friday
        duration_mins = 3 * 24 * 60 # 3 days (Friday to Monday)
        quantity = 1

        slots = described_class.available_slots(
          rental: rental_product,
          date: date,
          duration_mins: duration_mins,
          quantity: quantity
        )

        # Should be empty because rental crosses Saturday and Sunday which have no availability
        # The available?() check validates the multi-day period
        expect(slots).to be_empty
      end

      it 'generates slots for 1-day (24-hour) rental' do
        date = next_monday
        duration_mins = 24 * 60 # Exactly 24 hours
        quantity = 1

        slots = described_class.available_slots(
          rental: rental_product,
          date: date,
          duration_mins: duration_mins,
          quantity: quantity
        )

        # 24-hour is considered multi-day (>= 24 hours)
        # Should generate slots throughout the availability window
        expect(slots).not_to be_empty

        Time.use_zone(business.time_zone) do
          first_slot = slots.first
          last_slot = slots.last

          # Pickup Monday 9am, return Tuesday 9am
          expect(first_slot[:start_time]).to eq(date.in_time_zone.change(hour: 9, min: 0))
          expect(first_slot[:end_time]).to eq((date + 1.day).in_time_zone.change(hour: 9, min: 0))

          # Pickup Monday 5pm, return Tuesday 5pm
          expect(last_slot[:start_time]).to eq(date.in_time_zone.change(hour: 17, min: 0))
          expect(last_slot[:end_time]).to eq((date + 1.day).in_time_zone.change(hour: 17, min: 0))
        end
      end
    end

    context 'Edge case: 23.5 hour rental (just under 24 hours)' do
      it 'treats as single-day rental and requires full duration to fit' do
        date = next_monday
        duration_mins = (23.5 * 60).to_i # 1410 minutes
        quantity = 1

        slots = described_class.available_slots(
          rental: rental_product,
          date: date,
          duration_mins: duration_mins,
          quantity: quantity
        )

        # Single-day logic: must fit within the 9am-5pm (480 minute) window
        # 1410 minutes cannot fit in 480 minutes, so no slots
        expect(slots).to be_empty
      end
    end
  end
end
