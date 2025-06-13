class ExperienceTipReminderJob < ApplicationJob
  queue_as :default
  
  def perform(booking_id)
    @booking_id = booking_id
    return unless booking&.completed? && booking&.service&.experience? && booking&.service&.tips_enabled?
    return if booking.tip_reminder_sent_at.present?
    
    # Only send reminder if no tip has been collected yet
    return if booking.tip.present?
    
    ExperienceMailer.tip_reminder(booking).deliver_now
    booking.update!(tip_reminder_sent_at: Time.current)
    Rails.logger.info "Experience tip reminder sent for booking #{@booking_id}"
  rescue StandardError => e
    Rails.logger.error "Failed to send experience tip reminder for booking #{@booking_id}: #{e.message}"
    raise e # Re-raise to trigger retry mechanism
  end

  private

  def booking
    @booking ||= Booking.find_by(id: @booking_id)
  end
end 