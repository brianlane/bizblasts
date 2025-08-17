class ExperienceTipReminderJob < ApplicationJob
  queue_as :default
  
  def perform(booking_id)
    @booking_id = booking_id
    # Updated: Removed experience-only restriction, now works for all service types with tips enabled
    # Previously: Required booking&.service&.experience?
    return unless booking&.completed? && booking&.service&.tips_enabled?
    return if booking.tip_reminder_sent_at.present?
    
    # Only send reminder if no tip has been collected yet (separate tip record)
    return if booking.tip.present?
    
    # NEW: Check if tip was received on initial payment - if so, don't send mailer
    # Check invoice first, then check any order that belongs to this booking
    if booking.invoice&.tip_received_on_initial_payment?
      Rails.logger.info "Skipping tip reminder for booking #{@booking_id} - tip already received on initial payment (via invoice)"
      return
    end
    
    # Check if any order associated with this booking received a tip
    associated_order = Order.find_by(booking: booking)
    if associated_order&.tip_received_on_initial_payment?
      Rails.logger.info "Skipping tip reminder for booking #{@booking_id} - tip already received on initial payment (via order)"
      return
    end
    
    # NEW: Check business-level and service-level tip mailer settings
    business = booking.business
    service = booking.service
    
    # Check if business allows tip mailers when no tip received initially
    return unless business.tip_mailer_if_no_tip_received?
    
    # Check if service allows tip mailers when no tip received initially
    return unless service.tip_mailer_if_no_tip_received?
    
    ExperienceMailer.tip_reminder(booking).deliver_now
    booking.update!(tip_reminder_sent_at: Time.current)
    Rails.logger.info "Tip reminder sent for booking #{@booking_id} (service type: #{booking.service.service_type})"
  rescue StandardError => e
    Rails.logger.error "Failed to send tip reminder for booking #{@booking_id}: #{e.message}"
    raise e # Re-raise to trigger retry mechanism
  end

  private

  def booking
    @booking ||= Booking.find_by(id: @booking_id)
  end
end 