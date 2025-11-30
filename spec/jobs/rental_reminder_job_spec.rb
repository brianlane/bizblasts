# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RentalReminderJob, type: :job do
  let(:business) { create(:business) }
  let(:rental_product) { create(:product, :rental, business: business, rental_quantity_available: 5) }
  let(:customer) { create(:tenant_customer, business: business) }

  before do
    ActsAsTenant.current_tenant = business
    # Mock email and SMS delivery to avoid actual sends
    allow(RentalMailer).to receive(:pickup_reminder).and_return(double(deliver_later: true))
    allow(RentalMailer).to receive(:return_reminder).and_return(double(deliver_later: true))
    allow(SmsService).to receive(:send_rental_pickup_reminder).and_return(true)
    allow(SmsService).to receive(:send_rental_return_reminder).and_return(true)
  end

  describe 'pickup reminder deduplication' do
    let!(:booking) do
      create(:rental_booking,
        business: business,
        product: rental_product,
        tenant_customer: customer,
        status: 'deposit_paid',
        start_time: Date.tomorrow.noon,
        end_time: Date.tomorrow.noon + 2.hours
      )
    end

    it 'sends pickup reminder on first run' do
      expect(RentalMailer).to receive(:pickup_reminder).with(booking)
      expect(SmsService).to receive(:send_rental_pickup_reminder).with(booking)

      RentalReminderJob.perform_now

      expect(booking.reload.notes).to include("Pickup reminder sent: #{Date.current}")
    end

    it 'does not send duplicate pickup reminder on same day' do
      # First run - should send
      RentalReminderJob.perform_now
      expect(booking.reload.notes).to include("Pickup reminder sent: #{Date.current}")

      # Reset mocks
      allow(RentalMailer).to receive(:pickup_reminder).and_return(double(deliver_later: true))
      allow(SmsService).to receive(:send_rental_pickup_reminder).and_return(true)

      # Second run on same day - should NOT send
      expect(RentalMailer).not_to receive(:pickup_reminder)
      expect(SmsService).not_to receive(:send_rental_pickup_reminder)

      RentalReminderJob.perform_now
    end

    it 'sends pickup reminder again on different day' do
      # First run
      booking.update!(notes: "Pickup reminder sent: #{Date.yesterday}")

      # Should send again today
      expect(RentalMailer).to receive(:pickup_reminder).with(booking)
      expect(SmsService).to receive(:send_rental_pickup_reminder).with(booking)

      RentalReminderJob.perform_now

      expect(booking.reload.notes).to include("Pickup reminder sent: #{Date.current}")
    end

    it 'uses last date when multiple pickup reminders exist in notes' do
      # Simulate multiple pickup reminders over several days
      booking.update!(notes: "Pickup reminder sent: #{3.days.ago.to_date}\nPickup reminder sent: #{2.days.ago.to_date}\nPickup reminder sent: #{Date.yesterday}")

      # Should send again today because last entry was yesterday
      expect(RentalMailer).to receive(:pickup_reminder).with(booking)
      expect(SmsService).to receive(:send_rental_pickup_reminder).with(booking)

      RentalReminderJob.perform_now

      expect(booking.reload.notes).to include("Pickup reminder sent: #{Date.current}")
    end

    it 'does not send when last pickup reminder in multiple entries is today' do
      # Simulate multiple reminders with last one being today
      booking.update!(notes: "Pickup reminder sent: #{3.days.ago.to_date}\nPickup reminder sent: #{2.days.ago.to_date}\nPickup reminder sent: #{Date.current}")

      # Should NOT send because last entry is today
      expect(RentalMailer).not_to receive(:pickup_reminder)
      expect(SmsService).not_to receive(:send_rental_pickup_reminder)

      RentalReminderJob.perform_now
    end
  end

  describe 'return reminder deduplication' do
    let!(:booking) do
      create(:rental_booking,
        business: business,
        product: rental_product,
        tenant_customer: customer,
        status: 'checked_out',
        start_time: 2.days.ago,
        end_time: 12.hours.from_now
      )
    end

    it 'sends return reminder within reminder window' do
      expect(RentalMailer).to receive(:return_reminder).with(booking)
      expect(SmsService).to receive(:send_rental_return_reminder).with(booking)

      RentalReminderJob.perform_now

      expect(booking.reload.notes).to include("Return reminder sent: #{Date.current}")
    end

    it 'does not send duplicate return reminder on same day' do
      # First run
      RentalReminderJob.perform_now
      expect(booking.reload.notes).to include("Return reminder sent: #{Date.current}")

      # Reset mocks
      allow(RentalMailer).to receive(:return_reminder).and_return(double(deliver_later: true))
      allow(SmsService).to receive(:send_rental_return_reminder).and_return(true)

      # Second run - should NOT send
      expect(RentalMailer).not_to receive(:return_reminder)
      expect(SmsService).not_to receive(:send_rental_return_reminder)

      RentalReminderJob.perform_now
    end

    it 'uses last date when multiple return reminders exist in notes' do
      # Simulate multiple return reminders over several days
      booking.update!(notes: "Return reminder sent: #{3.days.ago.to_date}\nReturn reminder sent: #{2.days.ago.to_date}\nReturn reminder sent: #{Date.yesterday}")

      # Should send again today because last entry was yesterday
      expect(RentalMailer).to receive(:return_reminder).with(booking)
      expect(SmsService).to receive(:send_rental_return_reminder).with(booking)

      RentalReminderJob.perform_now

      expect(booking.reload.notes).to include("Return reminder sent: #{Date.current}")
    end

    it 'does not send when last return reminder in multiple entries is today' do
      # Simulate multiple reminders with last one being today
      booking.update!(notes: "Return reminder sent: #{3.days.ago.to_date}\nReturn reminder sent: #{2.days.ago.to_date}\nReturn reminder sent: #{Date.current}")

      # Should NOT send because last entry is today
      expect(RentalMailer).not_to receive(:return_reminder)
      expect(SmsService).not_to receive(:send_rental_return_reminder)

      RentalReminderJob.perform_now
    end
  end
end
