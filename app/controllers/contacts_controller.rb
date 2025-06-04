# frozen_string_literal: true

class ContactsController < ApplicationController
  # Skip authentication for the contact form
  skip_before_action :authenticate_user!, raise: false
  # Security: Remove CSRF skip - use proper protection instead
  # skip_before_action :verify_authenticity_token, only: [:create] # REMOVED FOR SECURITY

  # Security: Add rate limiting hook (implement with rack-attack)
  # before_action :check_contact_rate_limit, only: [:create]

  def create
    # Security: Use strong parameters instead of direct access
    contact_params = sanitized_contact_params
    
    # Security: Validate parameters (enhanced validation)
    if contact_params[:name].blank? || contact_params[:email].blank? || 
       contact_params[:subject].blank? || contact_params[:message].blank?
      flash[:alert] = "Please fill in all required fields (Name, Email, Subject, Message)."
      redirect_to contact_url
      return
    end

    # Security: Validate email format
    unless contact_params[:email].match?(/\A[^@\s]+@[^@\s]+\z/)
      flash[:alert] = "Please provide a valid email address."
      redirect_to contact_url
      return
    end

    # Security: Length limits to prevent abuse
    if contact_params[:message].length > 5000
      flash[:alert] = "Message is too long. Please limit to 5000 characters."
      redirect_to contact_url
      return
    end

    # Security: Log contact attempts for monitoring
    Rails.logger.info "[CONTACT] Contact form submission from IP: #{request.remote_ip}, Email: #{contact_params[:email]}"

    # Send email with sanitized content
    begin
      ContactMailer.contact_message(
        contact_params[:name], 
        contact_params[:email], 
        contact_params[:business_name], 
        contact_params[:subject], 
        contact_params[:message]
      ).deliver_now
      flash[:notice] = "Your message has been sent successfully!"
    rescue StandardError => e
      # Handle email sending errors
      Rails.logger.error "Failed to send contact email: #{e.message}"
      flash[:alert] = "There was an error sending your message. Please try again later."
    end

    # Redirect back to the contact page
    redirect_to contact_url
  end

  private

  # Security: Strong parameters with sanitization
  def sanitized_contact_params
    permitted = params.permit(:name, :email, :business_name, :subject, :message)
    
    # Sanitize text fields to remove potentially dangerous content
    permitted.each do |key, value|
      if value.is_a?(String)
        # Remove control characters but preserve newlines for message
        if key == 'message'
          permitted[key] = value.gsub(/[[:cntrl:]&&[^\n\r\t]]/, '').strip
        else
          permitted[key] = value.gsub(/[[:cntrl:]]/, '').strip.squeeze(' ')
        end
        
        # Log suspiciously long inputs
        if value.length > 500 && key != 'message'
          Rails.logger.warn "[SECURITY] Unusually long #{key} in contact form from IP: #{request.remote_ip}"
        end
      end
    end
    
    permitted
  end

  # Security: Rate limiting check (implement with rack-attack gem)
  # def check_contact_rate_limit
  #   # Example implementation:
  #   # throttle('contact_form/ip', limit: 5, period: 1.hour) do |req|
  #   #   req.ip if req.path == '/contact' && req.post?
  #   # end
  # end
end 