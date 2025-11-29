# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Product, 'multi-day rental availability schedule', type: :model do
  let(:business) { create(:business, time_zone: 'America/New_York') }

  let(:rental_product) do
    create(:product, :rental,
      business: business,
      rental_quantity_available: 5,
      allow_daily_rental: true,
      allow_weekly_rental: true,
      min_rental_duration_mins: 24 * 60, # 1 day
      max_rental_duration_mins: 7 * 24 * 60 # 1 week
    )
  end

  # Schedule with availability Monday-Friday 9am-5pm
  let(:weekday_schedule) do
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

  describe '#rental_schedule_allows?' do
    context 'with no availability schedule configured' do
      it 'allows any time period' do
        Time.use_zone(business.time_zone) do
          start_time = Time.zone.parse('2025-01-06 10:00') # Monday
          end_time = Time.zone.parse('2025-01-08 16:00')   # Wednesday

          expect(rental_product.rental_schedule_allows?(start_time, end_time)).to be true
        end
      end
    end

    context 'with weekday availability schedule' do
      before do
        rental_product.update!(rental_availability_schedule: weekday_schedule)
      end

      context 'single-day rentals' do
        it 'allows rental within available hours' do
          Time.use_zone(business.time_zone) do
            start_time = Time.zone.parse('2025-01-06 10:00') # Monday 10am
            end_time = Time.zone.parse('2025-01-06 15:00')   # Monday 3pm

            expect(rental_product.rental_schedule_allows?(start_time, end_time)).to be true
          end
        end

        it 'rejects rental outside available hours' do
          Time.use_zone(business.time_zone) do
            start_time = Time.zone.parse('2025-01-06 08:00') # Monday 8am (before 9am)
            end_time = Time.zone.parse('2025-01-06 10:00')   # Monday 10am

            expect(rental_product.rental_schedule_allows?(start_time, end_time)).to be false
          end
        end

        it 'rejects rental on day with no availability' do
          Time.use_zone(business.time_zone) do
            start_time = Time.zone.parse('2025-01-04 10:00') # Saturday 10am
            end_time = Time.zone.parse('2025-01-04 15:00')   # Saturday 3pm

            expect(rental_product.rental_schedule_allows?(start_time, end_time)).to be false
          end
        end
      end

      context 'multi-day rentals' do
        it 'allows 2-day rental when both days have availability' do
          Time.use_zone(business.time_zone) do
            start_time = Time.zone.parse('2025-01-06 10:00') # Monday 10am
            end_time = Time.zone.parse('2025-01-07 15:00')   # Tuesday 3pm

            expect(rental_product.rental_schedule_allows?(start_time, end_time)).to be true
          end
        end

        it 'allows 3-day rental when all days have availability' do
          Time.use_zone(business.time_zone) do
            start_time = Time.zone.parse('2025-01-06 10:00') # Monday 10am
            end_time = Time.zone.parse('2025-01-08 15:00')   # Wednesday 3pm

            expect(rental_product.rental_schedule_allows?(start_time, end_time)).to be true
          end
        end

        it 'allows 5-day weekday rental' do
          Time.use_zone(business.time_zone) do
            start_time = Time.zone.parse('2025-01-06 10:00') # Monday 10am
            end_time = Time.zone.parse('2025-01-10 15:00')   # Friday 3pm

            expect(rental_product.rental_schedule_allows?(start_time, end_time)).to be true
          end
        end

        it 'rejects rental when first day lacks availability' do
          Time.use_zone(business.time_zone) do
            start_time = Time.zone.parse('2025-01-04 10:00') # Saturday 10am (no availability)
            end_time = Time.zone.parse('2025-01-06 15:00')   # Monday 3pm

            expect(rental_product.rental_schedule_allows?(start_time, end_time)).to be false
          end
        end

        it 'rejects rental when middle day lacks availability' do
          Time.use_zone(business.time_zone) do
            start_time = Time.zone.parse('2025-01-03 10:00') # Friday 10am
            end_time = Time.zone.parse('2025-01-06 15:00')   # Monday 3pm
            # This crosses Saturday and Sunday which have no availability

            expect(rental_product.rental_schedule_allows?(start_time, end_time)).to be false
          end
        end

        it 'rejects rental when last day lacks availability' do
          Time.use_zone(business.time_zone) do
            start_time = Time.zone.parse('2025-01-03 10:00') # Friday 10am
            end_time = Time.zone.parse('2025-01-04 15:00')   # Saturday 3pm (no availability)

            expect(rental_product.rental_schedule_allows?(start_time, end_time)).to be false
          end
        end

        it 'rejects rental when start_time is before first day availability opens' do
          Time.use_zone(business.time_zone) do
            start_time = Time.zone.parse('2025-01-06 08:00') # Monday 8am (before 9am)
            end_time = Time.zone.parse('2025-01-07 15:00')   # Tuesday 3pm

            expect(rental_product.rental_schedule_allows?(start_time, end_time)).to be false
          end
        end

        it 'rejects rental when end_time is after last day availability closes' do
          Time.use_zone(business.time_zone) do
            start_time = Time.zone.parse('2025-01-06 10:00') # Monday 10am
            end_time = Time.zone.parse('2025-01-07 18:00')   # Tuesday 6pm (after 5pm)

            expect(rental_product.rental_schedule_allows?(start_time, end_time)).to be false
          end
        end
      end

      context 'with schedule exceptions' do
        let(:schedule_with_exception) do
          weekday_schedule.merge(
            exceptions: {
              '2025-01-07' => [] # Tuesday closed
            }
          )
        end

        before do
          rental_product.update!(rental_availability_schedule: schedule_with_exception)
        end

        it 'rejects multi-day rental when exception day has no availability' do
          Time.use_zone(business.time_zone) do
            start_time = Time.zone.parse('2025-01-06 10:00') # Monday 10am
            end_time = Time.zone.parse('2025-01-08 15:00')   # Wednesday 3pm
            # Crosses Tuesday which is closed via exception

            expect(rental_product.rental_schedule_allows?(start_time, end_time)).to be false
          end
        end
      end
    end

    context 'with multiple time slots per day' do
      let(:split_schedule) do
        {
          monday: [
            { start: '09:00', end: '12:00' },
            { start: '13:00', end: '17:00' }
          ],
          tuesday: [
            { start: '09:00', end: '12:00' },
            { start: '13:00', end: '17:00' }
          ]
        }
      end

      before do
        rental_product.update!(rental_availability_schedule: split_schedule)
      end

      it 'allows multi-day rental when each day has at least one slot' do
        Time.use_zone(business.time_zone) do
          start_time = Time.zone.parse('2025-01-06 10:00') # Monday 10am
          end_time = Time.zone.parse('2025-01-07 15:00')   # Tuesday 3pm

          expect(rental_product.rental_schedule_allows?(start_time, end_time)).to be true
        end
      end
    end
  end

  describe '#rental_available_for?' do
    before do
      rental_product.update!(rental_availability_schedule: weekday_schedule)
    end

    it 'integrates schedule check with quantity check for multi-day rentals' do
      Time.use_zone(business.time_zone) do
        start_time = Time.zone.parse('2025-01-06 10:00') # Monday 10am
        end_time = Time.zone.parse('2025-01-07 15:00')   # Tuesday 3pm

        # Should pass schedule check and have quantity available
        expect(rental_product.rental_available_for?(start_time, end_time, quantity: 2)).to be true
      end
    end

    it 'rejects multi-day rental when schedule check fails' do
      Time.use_zone(business.time_zone) do
        start_time = Time.zone.parse('2025-01-04 10:00') # Saturday 10am (no availability)
        end_time = Time.zone.parse('2025-01-06 15:00')   # Monday 3pm

        # Should fail schedule check
        expect(rental_product.rental_available_for?(start_time, end_time, quantity: 1)).to be false
      end
    end

    it 'rejects multi-day rental when quantity is insufficient' do
      Time.use_zone(business.time_zone) do
        # Create bookings that consume all available quantity
        5.times do |i|
          create(:rental_booking,
            product: rental_product,
            business: business,
            start_time: Time.zone.parse('2025-01-06 09:00'),
            end_time: Time.zone.parse('2025-01-07 17:00'),
            quantity: 1,
            status: 'deposit_paid'
          )
        end

        start_time = Time.zone.parse('2025-01-06 10:00') # Monday 10am
        end_time = Time.zone.parse('2025-01-07 15:00')   # Tuesday 3pm

        # Should pass schedule check but fail quantity check
        expect(rental_product.rental_available_for?(start_time, end_time, quantity: 1)).to be false
      end
    end
  end
end
