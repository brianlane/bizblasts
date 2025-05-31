# frozen_string_literal: true

class ContactsController < ApplicationController
  # Skip authentication for the contact form
  skip_before_action :authenticate_user!, raise: false
  skip_before_action :verify_authenticity_token, only: [:create] # Consider more robust CSRF protection if needed

  def create
    # Extract form parameters
    @name = params[:name]
    @email = params[:email]
    @business_name = params[:business_name]
    @subject = params[:subject]
    @message = params[:message]

    # Validate parameters (basic validation)
    if @name.blank? || @email.blank? || @subject.blank? || @message.blank?
      # Handle validation errors - maybe re-render the form with an error message
      flash[:alert] = "Please fill in all required fields (Name, Email, Subject, Message)."
      redirect_to contact_url # Use _url helper for redirects in controllers
      return
    end

    # Send email
    begin
      ContactMailer.contact_message(@name, @email, @business_name, @subject, @message).deliver_now
      flash[:notice] = "Your message has been sent successfully!"
    rescue StandardError => e
      # Handle email sending errors
      Rails.logger.error "Failed to send contact email: #{e.message}"
      flash[:alert] = "There was an error sending your message. Please try again later."
    end

    # Redirect back to the contact page
    redirect_to contact_url # Use _url helper for redirects in controllers
  end

  private

  # Strong parameters are not strictly necessary for this simple case
  # if we are assigning directly from params, but it's good practice.
  # However, since we're just passing them to the mailer, direct assignment is fine.
  # def contact_params
  #   params.permit(:name, :email, :business_name, :subject, :message)
  # end
end 