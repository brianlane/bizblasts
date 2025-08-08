# frozen_string_literal: true

# ReviewRequestMailer handles sending Google-policy compliant review requests
# 
# Google Policy Requirements:
# - Neutral language that doesn't bias toward positive reviews
# - Direct link to Google for review writing
# - One-time request per booking/order with unsubscribe option
# - No incentivization or pressure for positive reviews
class ReviewRequestMailer < ApplicationMailer
  
  # Send a review request email after successful payment
  # @param request_data [Hash] Contains business, customer, booking/order, and tracking token
  def review_request_email(request_data)
    @business = request_data[:business]
    @customer = request_data[:customer] 
    @booking = request_data[:booking]
    @order = request_data[:order]
    @invoice = request_data[:invoice]
    @tracking_token = request_data[:tracking_token]
    
    # Validate required data
    return unless @business.present? && @customer.present?
    return unless @business.google_place_id.present?
    return unless @tracking_token.present?
    
    # Check if customer can receive review request emails
    return unless @customer.can_receive_email?(:customer)
    
    # Generate the Google review URL
    @review_url = "https://search.google.com/local/writereview?placeid=#{@business.google_place_id}"
    
    # Set unsubscribe token for the customer
    set_unsubscribe_token(@customer)
    
    # Determine service name for personalization (optional)
    @service_name = if @booking&.service
      @booking.service.name
    elsif @order&.service_line_items&.any?
      service_names = @order.service_line_items.map { |item| item.service&.name }.compact
      service_names.first # Use first service name for simplicity
    end
    
    mail(
      to: @customer.email,
      subject: subject_line,
      template_path: 'review_request_mailer',
      template_name: 'review_request_email'
    )
    
  rescue => e
    Rails.logger.error "[ReviewRequestMailer] Failed to send review request to #{@customer&.email}: #{e.message}"
    nil
  end
  
  private
  
  # Generate neutral subject line (Google Policy compliant)
  def subject_line
    if @service_name.present?
      "Thank you for choosing #{@business.name} - Share your experience"
    else
      "Thank you for choosing #{@business.name}"
    end
  end
end