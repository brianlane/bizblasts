class SendPaymentRemindersJob < ApplicationJob
  queue_as :default

  def perform
    # Send reminders for experience services that require immediate payment
    send_experience_service_reminders
    
    # Send optional reminders for standard services
    send_standard_service_reminders
  end

  private

  def send_experience_service_reminders
    # Find experience service bookings with unpaid invoices
    experience_bookings = Booking.joins(:service, :invoice)
                                .where(services: { service_type: :experience })
                                .where(invoices: { status: [:pending, :overdue] })
                                .where('bookings.start_time > ?', Time.current)
                                .includes(:service, :business, :tenant_customer, :invoice)

    experience_bookings.find_each do |booking|
      # Send immediate payment reminders for experience services
      # More frequent reminders since payment is required
      hours_until_booking = ((booking.start_time - Time.current) / 1.hour).round
      
      # Send reminders at: 48h, 24h, 12h, 6h, 2h before booking
      reminder_hours = [48, 24, 12, 6, 2]
      
      if reminder_hours.include?(hours_until_booking)
        # Only send email reminders if customer has an email address
        if booking.tenant_customer.email.present?
          Rails.logger.info "[SendPaymentRemindersJob] Sending experience payment reminder for booking ##{booking.id} (#{hours_until_booking}h before)"
          BookingMailer.payment_reminder(booking).deliver_later
        else
          Rails.logger.info "[SendPaymentRemindersJob] Skipping email reminder for booking ##{booking.id} - no email address"
        end
      end
    end
  end

  def send_standard_service_reminders
    # Find standard service bookings with unpaid invoices
    standard_bookings = Booking.joins(:service, :invoice)
                              .where(services: { service_type: :standard })
                              .where(invoices: { status: [:pending, :overdue] })
                              .where('bookings.start_time > ?', Time.current)
                              .includes(:service, :business, :tenant_customer, :invoice)

    standard_bookings.find_each do |booking|
      # Send gentle reminders for standard services (payment is optional)
      # Less frequent since payment is not required to maintain booking
      hours_until_booking = ((booking.start_time - Time.current) / 1.hour).round
      
      # Send reminders at: 7 days, 3 days, 1 day before booking
      reminder_hours = [168, 72, 24] # 7*24, 3*24, 1*24
      
      if reminder_hours.include?(hours_until_booking)
        # Only send email reminders if customer has an email address
        if booking.tenant_customer.email.present?
          Rails.logger.info "[SendPaymentRemindersJob] Sending standard payment reminder for booking ##{booking.id} (#{hours_until_booking}h before)"
          BookingMailer.payment_reminder(booking).deliver_later
        else
          Rails.logger.info "[SendPaymentRemindersJob] Skipping email reminder for booking ##{booking.id} - no email address"
        end
      end
    end
  end
end 