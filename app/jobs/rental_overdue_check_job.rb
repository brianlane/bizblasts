# frozen_string_literal: true

class RentalOverdueCheckJob < ApplicationJob
  queue_as :default
  
  # This job checks for overdue rentals and sends notifications
  # It should be run periodically (e.g., every hour) via recurring schedule
  def perform
    Rails.logger.info("[RentalOverdueCheckJob] Starting overdue check")
    
    overdue_count = 0
    notification_count = 0
    
    # Find all rentals that are checked out and past their return time
    RentalBooking.status_checked_out.where('end_time < ?', Time.current).find_each do |booking|
      # Mark as overdue
      booking.mark_overdue!
      overdue_count += 1
      
      # Send overdue notification if not already sent today
      last_notification = booking.notes&.match(/Overdue notification sent: (\d{4}-\d{2}-\d{2})/)
      last_date = last_notification ? Date.parse(last_notification[1]) : nil
      
      if last_date != Date.current
        RentalMailer.overdue_notice(booking).deliver_later
        booking.update!(notes: [booking.notes, "Overdue notification sent: #{Date.current}"].compact.join("\n"))
        notification_count += 1
      end
    end
    
    Rails.logger.info("[RentalOverdueCheckJob] Completed: #{overdue_count} marked overdue, #{notification_count} notifications sent")
  end
end

