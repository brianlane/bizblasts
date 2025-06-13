class ExperienceMailer < ApplicationMailer
  def tip_reminder(booking)
    @booking = booking
    @business = booking.business
    @customer = booking.tenant_customer
    @service = booking.service
    
    # Generate secure tip collection URL
    @tip_url = new_tip_url(
      booking_id: @booking.id,
      token: @booking.generate_tip_token,
      host: "#{@business.subdomain}.#{Rails.application.config.default_domain}"
    )
    
    # Set business context for email styling
    @business_logo = @business.logo.attached? ? url_for(@business.logo) : nil
    @business_colors = {
      primary: @business.primary_color || '#3B82F6',
      secondary: @business.secondary_color || '#1F2937'
    }
    
    mail(
      to: @customer.email,
      subject: "Thank you for choosing #{@business.name} - Share your appreciation",
      from: "#{@business.name} <noreply@#{@business.subdomain}.#{Rails.application.config.default_domain}>",
      reply_to: @business.email
    )
  end
end 