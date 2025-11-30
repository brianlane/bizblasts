# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RentalBookingService, type: :service do
  let(:business) { create(:business) }
  let(:rental_product) { create(:product, :rental, business: business, rental_quantity_available: 5, price: 50) }
  let(:customer) { create(:tenant_customer, business: business) }

  before do
    ActsAsTenant.current_tenant = business
  end

  describe '#update_booking' do
    let(:booking) do
      create(:rental_booking,
        business: business,
        product: rental_product,
        tenant_customer: customer,
        quantity: 2,
        start_time: 1.day.from_now,
        end_time: 1.day.from_now + 2.hours,
        status: 'deposit_paid'
      )
    end

    let(:service) { described_class.new(rental: rental_product, tenant_customer: customer, params: update_params) }

    context 'when updating only quantity' do
      let(:update_params) { { quantity: 3 } }

      it 'checks availability for the new quantity' do
        expect(RentalAvailabilityService).to receive(:available?).with(
          rental: rental_product,
          start_time: booking.start_time,
          end_time: booking.end_time,
          quantity: 3,
          exclude_booking_id: booking.id
        ).and_return(true)

        result = service.update_booking(booking)

        expect(result[:success]).to be true
        expect(booking.reload.quantity).to eq(3)
      end

      it 'rejects update when new quantity exceeds availability' do
        # Mock availability check to return false (not enough inventory)
        allow(RentalAvailabilityService).to receive(:available?).and_return(false)

        result = service.update_booking(booking)

        expect(result[:success]).to be false
        expect(result[:errors]).to include("The rental is not available for the new dates")
        expect(booking.reload.quantity).to eq(2) # Should remain unchanged
      end

      it 'allows quantity increase within available inventory' do
        # 5 total available, 2 currently booked, can increase to 5
        update_service = described_class.new(rental: rental_product, tenant_customer: customer, params: { quantity: 5 })

        result = update_service.update_booking(booking)

        expect(result[:success]).to be true
        expect(booking.reload.quantity).to eq(5)
      end

      it 'prevents quantity increase beyond available inventory' do
        # 5 total available, trying to book 6 should fail
        update_service = described_class.new(rental: rental_product, tenant_customer: customer, params: { quantity: 6 })
        allow(RentalAvailabilityService).to receive(:available?).and_return(false)

        result = update_service.update_booking(booking)

        expect(result[:success]).to be false
        expect(booking.reload.quantity).to eq(2) # Should remain unchanged
      end
    end

    context 'when updating dates and quantity together' do
      let(:update_params) do
        {
          start_time: 2.days.from_now,
          end_time: 2.days.from_now + 3.hours,
          quantity: 4
        }
      end

      it 'checks availability for both new dates and quantity' do
        new_start = 2.days.from_now
        new_end = 2.days.from_now + 3.hours

        expect(RentalAvailabilityService).to receive(:available?).with(
          rental: rental_product,
          start_time: an_instance_of(ActiveSupport::TimeWithZone),
          end_time: an_instance_of(ActiveSupport::TimeWithZone),
          quantity: 4,
          exclude_booking_id: booking.id
        ).and_return(true)

        result = service.update_booking(booking)

        expect(result[:success]).to be true
        expect(booking.reload.quantity).to eq(4)
      end
    end

    context 'when updating with duration_mins' do
      let(:start_time) { 3.days.from_now.noon }
      let(:update_params) do
        {
          start_time: start_time,
          duration_mins: 180, # 3 hours
          quantity: 3
        }
      end

      it 'converts duration_mins to end_time and checks availability' do
        result = service.update_booking(booking)

        expect(result[:success]).to be true
        booking.reload
        expect(booking.quantity).to eq(3)
        expect(booking.end_time).to be_within(1.minute).of(start_time + 180.minutes)
      end
    end
  end
end
