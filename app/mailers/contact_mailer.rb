# frozen_string_literal: true

class ContactMailer < ApplicationMailer
  def contact_message(name, email, business_name, subject, message)
    @name = name
    @email = email
    @business_name = business_name
    @subject = subject
    @message = message

    mail(to: ENV['SUPPORT_EMAIL'],
         from: email, # Set reply-to to the sender's email
         subject: "New Contact Form Message: #{subject}",
         reply_to: @support_email)
  end
end 