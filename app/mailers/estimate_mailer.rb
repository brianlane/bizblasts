# frozen_string_literal: true

class EstimateMailer < ApplicationMailer
  default from: ENV.fetch('MAILER_EMAIL', 'no-reply@example.com')

  # Sends the estimate to the customer
  def send_estimate(estimate)
    @estimate = estimate
    @url = public_estimate_url(token: @estimate.token, host: "#{@estimate.business.subdomain}.#{Rails.application.config.main_domain}")
    mail(to: @estimate.customer_email, subject: "Your Estimate ##{@estimate.id} from #{estimate.business.name}")
  end

  # Notifies customer their estimate was approved
  def estimate_approved(estimate)
    @estimate = estimate
    mail(to: @estimate.customer_email, subject: "Estimate ##{@estimate.id} Approved")
  end

  # Notifies customer their estimate was declined
  def estimate_declined(estimate)
    @estimate = estimate
    mail(to: @estimate.customer_email, subject: "Estimate ##{@estimate.id} Declined")
  end

  # Notifies business of requested changes
  def request_changes_notification(estimate, message)
    @estimate = estimate
    @message = message
    # Get emails from business managers (admin_users association doesn't exist on Business)
    manager_emails = estimate.business.users.where(role: :manager).pluck(:email)
    return if manager_emails.empty?

    mail(to: manager_emails, subject: "Change Request for Estimate ##{estimate.id}")
  end
end 