# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Product, 'slot boundary validation for multi-day rentals', type: :model do
  let(:business) { create(:business, time_zone: 'America/New_York') }

  let(:rental_product) do
    create(:product, :rental,
      business: business,
      rental_quantity_available: 5,
      allow_daily_rental: true,
      min_rental_duration_mins: 24 * 60,
      max_rental_duration_mins: 7 * 24 * 60,
      rental_availability_schedule: availability_schedule
    )
  end

  # Schedule with 8am-10am slot only
  let(:availability_schedule) do
    {
      monday: [{ start: '08:00', end: '10:00' }],
      tuesday: [{ start: '08:00', end: '10:00' }],
      wednesday: [{ start: '08:00', end: '10:00' }],
      thursday: [{ start: '08:00', end: '10:00' }],
      friday: [{ start: '08:00', end: '10:00' }],
      saturday: [],
      sunday: []
    }
  end

  describe '#rental_schedule_allows?' do
    context 'Bug Fix: First day slot boundary validation' do
      it 'rejects rental starting at 2pm when slot is 8am-10am (start_time outside slot)' do
        Time.use_zone(business.time_zone) do
          # Monday 2pm to Tuesday 9am
          start_time = Time.zone.parse('2025-01-06 14:00')
          end_time = Time.zone.parse('2025-01-07 09:00')

          # Before fix: would pass because slot[:start] (8am) <= start_time (2pm) was false,
          # but the check was only slot[:start] <= start_time without checking slot[:end]
          # After fix: properly checks slot[:start] <= start_time && slot[:end] > start_time
          expect(rental_product.rental_schedule_allows?(start_time, end_time)).to be false
        end
      end

      it 'allows rental starting at 9am when slot is 8am-10am (start_time within slot)' do
        Time.use_zone(business.time_zone) do
          # Monday 9am to Tuesday 9am
          start_time = Time.zone.parse('2025-01-06 09:00')
          end_time = Time.zone.parse('2025-01-07 09:00')

          # slot[:start] (8am) <= start_time (9am) && slot[:end] (10am) > start_time (9am)
          expect(rental_product.rental_schedule_allows?(start_time, end_time)).to be true
        end
      end

      it 'allows rental starting at 10am when slot is 8am-10am (start_time at slot end)' do
        Time.use_zone(business.time_zone) do
          # Monday 10am to Tuesday 9am
          start_time = Time.zone.parse('2025-01-06 10:00')
          end_time = Time.zone.parse('2025-01-07 09:00')

          # slot[:end] (10am) >= start_time (10am) is true - can pickup at closing time
          expect(rental_product.rental_schedule_allows?(start_time, end_time)).to be true
        end
      end
    end

    context 'Bug Fix: Last day slot boundary validation' do
      it 'rejects rental ending at 7am when slot is 8am-10am (end_time before slot)' do
        Time.use_zone(business.time_zone) do
          # Monday 9am to Tuesday 7am
          start_time = Time.zone.parse('2025-01-06 09:00')
          end_time = Time.zone.parse('2025-01-07 07:00')

          # Before fix: would pass because slot[:end] (10am) >= end_time (7am),
          # but didn't check if slot[:start] < end_time
          # After fix: properly checks slot[:start] < end_time && slot[:end] >= end_time
          expect(rental_product.rental_schedule_allows?(start_time, end_time)).to be false
        end
      end

      it 'allows rental ending at 9am when slot is 8am-10am (end_time within slot)' do
        Time.use_zone(business.time_zone) do
          # Monday 9am to Tuesday 9am
          start_time = Time.zone.parse('2025-01-06 09:00')
          end_time = Time.zone.parse('2025-01-07 09:00')

          # slot[:start] (8am) < end_time (9am) && slot[:end] (10am) >= end_time (9am)
          expect(rental_product.rental_schedule_allows?(start_time, end_time)).to be true
        end
      end

      it 'allows rental ending at 8am when slot is 8am-10am (end_time at slot start)' do
        Time.use_zone(business.time_zone) do
          # Monday 9am to Tuesday 8am
          start_time = Time.zone.parse('2025-01-06 09:00')
          end_time = Time.zone.parse('2025-01-07 08:00')

          # slot[:start] (8am) <= end_time (8am) is true - can return when shop opens
          expect(rental_product.rental_schedule_allows?(start_time, end_time)).to be true
        end
      end
    end

    context 'Edge cases for boundary validation' do
      it 'allows rental that exactly matches the availability slot' do
        Time.use_zone(business.time_zone) do
          # Monday 8am to Tuesday 10am
          start_time = Time.zone.parse('2025-01-06 08:00')
          end_time = Time.zone.parse('2025-01-07 10:00')

          expect(rental_product.rental_schedule_allows?(start_time, end_time)).to be true
        end
      end

      it 'rejects rental that starts before and ends after the slot' do
        Time.use_zone(business.time_zone) do
          # Monday 7am to Tuesday 11am (slot is 8am-10am)
          start_time = Time.zone.parse('2025-01-06 07:00')
          end_time = Time.zone.parse('2025-01-07 11:00')

          expect(rental_product.rental_schedule_allows?(start_time, end_time)).to be false
        end
      end
    end
  end
end
