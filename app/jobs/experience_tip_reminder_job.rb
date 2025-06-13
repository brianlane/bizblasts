class ExperienceTipReminderJob < ApplicationJob
  queue_as :default
  
  def perform(booking_id)
    booking = Booking.find_by(id: booking_id)
    return unless booking&.completed? && booking&.service&.experience? && booking&.service&.tips_enabled?
    
    # Only send if business has tips enabled
    return unless booking.business.tips_enabled?
    
    # Don't send if tip already collected
    return if booking.tip.present?
    
    # Don't send if reminder was already sent recently (within 48 hours)
    return if booking.tip_reminder_sent_at.present? && booking.tip_reminder_sent_at > 48.hours.ago
    
    begin
      # Send the tip reminder email
      ExperienceMailer.tip_reminder(booking).deliver_now
      
      # Update the reminder timestamp
      booking.update_column(:tip_reminder_sent_at, Time.current)
      
      Rails.logger.info("Experience tip reminder sent for booking #{booking.id}")
    rescue => e
      Rails.logger.error("Failed to send experience tip reminder for booking #{booking.id}: #{e.message}")
      raise e
    end
  end
end 