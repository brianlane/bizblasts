# frozen_string_literal: true

class EstimateMailer < ApplicationMailer
  default from: ENV.fetch('MAILER_EMAIL', 'no-reply@example.com')

  # Sends the estimate to the customer
  def send_estimate(estimate)
    @estimate = estimate
    @url = tenant_estimate_url(@estimate.token)
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
    mail(to: estimate.business.admin_users.pluck(:email), subject: "Change Request for Estimate ##{estimate.id}")
  end
end 