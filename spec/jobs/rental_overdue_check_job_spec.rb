# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RentalOverdueCheckJob, type: :job do
  let(:business) { create(:business) }
  let(:rental_product) { create(:product, :rental, business: business, rental_quantity_available: 5) }
  let(:customer) { create(:tenant_customer, business: business) }

  before do
    ActsAsTenant.current_tenant = business
    # Mock email delivery to avoid actual sends
    allow(RentalMailer).to receive(:overdue_notice).and_return(double(deliver_later: true))
  end

  describe 'overdue notification deduplication' do
    let!(:overdue_booking) do
      create(:rental_booking,
        business: business,
        product: rental_product,
        tenant_customer: customer,
        status: 'overdue',
        start_time: 3.days.ago,
        end_time: 1.day.ago
      )
    end

    it 'sends notification on first check for already overdue booking' do
      expect(RentalMailer).to receive(:overdue_notice).with(overdue_booking)

      RentalOverdueCheckJob.perform_now

      expect(overdue_booking.reload.notes).to include("Overdue notification sent: #{Date.current}")
    end

    it 'does not send duplicate notification on same day' do
      # First run
      RentalOverdueCheckJob.perform_now
      expect(overdue_booking.reload.notes).to include("Overdue notification sent: #{Date.current}")

      # Reset mock
      allow(RentalMailer).to receive(:overdue_notice).and_return(double(deliver_later: true))

      # Second run - should NOT send
      expect(RentalMailer).not_to receive(:overdue_notice)

      RentalOverdueCheckJob.perform_now
    end

    it 'sends notification again on different day' do
      # Simulate notification sent yesterday
      overdue_booking.update!(notes: "Overdue notification sent: #{Date.yesterday}")

      # Should send again today
      expect(RentalMailer).to receive(:overdue_notice).with(overdue_booking)

      RentalOverdueCheckJob.perform_now

      expect(overdue_booking.reload.notes).to include("Overdue notification sent: #{Date.current}")
    end

    it 'uses last date when multiple overdue notifications exist in notes' do
      # Simulate multiple overdue notifications over several days
      overdue_booking.update!(notes: "Overdue notification sent: #{5.days.ago.to_date}\nOverdue notification sent: #{3.days.ago.to_date}\nOverdue notification sent: #{Date.yesterday}")

      # Should send again today because last entry was yesterday
      expect(RentalMailer).to receive(:overdue_notice).with(overdue_booking)

      RentalOverdueCheckJob.perform_now

      expect(overdue_booking.reload.notes).to include("Overdue notification sent: #{Date.current}")
    end

    it 'does not send when last overdue notification in multiple entries is today' do
      # Simulate multiple notifications with last one being today
      overdue_booking.update!(notes: "Overdue notification sent: #{5.days.ago.to_date}\nOverdue notification sent: #{3.days.ago.to_date}\nOverdue notification sent: #{Date.current}")

      # Should NOT send because last entry is today
      expect(RentalMailer).not_to receive(:overdue_notice)

      RentalOverdueCheckJob.perform_now
    end
  end

  describe 'marking newly overdue rentals' do
    it 'marks checked_out booking as overdue and sends first notification' do
      # Create a checked_out booking that's overdue
      checked_out_booking = create(:rental_booking,
        business: business,
        product: rental_product,
        tenant_customer: customer,
        status: 'checked_out',
        start_time: 2.days.ago,
        end_time: 1.hour.ago  # Overdue by 1 hour
      )

      # Should call mark_overdue! which changes status and sends notification
      expect(RentalMailer).to receive(:overdue_notice).at_least(:once)

      RentalOverdueCheckJob.perform_now

      # Booking should now be marked as overdue
      expect(checked_out_booking.reload.status).to eq('overdue')
      expect(checked_out_booking.notes).to include("Overdue notification sent: #{Date.current}")
    end
  end
end
