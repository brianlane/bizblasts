# frozen_string_literal: true

class EstimateMailer < ApplicationMailer
  default from: ENV.fetch('MAILER_EMAIL', 'no-reply@example.com')

  # Sends the estimate to the customer with PDF attachment
  def send_estimate(estimate)
    @estimate = estimate
    @business = estimate.business
    @url = public_estimate_url(token: @estimate.token, host: "#{@business.subdomain}.#{Rails.application.config.main_domain}")

    # Attach PDF if available
    if @estimate.pdf.attached?
      attachments["#{@estimate.estimate_number || 'Estimate'}.pdf"] = @estimate.pdf.download
    end

    mail(
      to: @estimate.customer_email,
      subject: "#{@business.name} - Estimate #{@estimate.estimate_number || "##{@estimate.id}"}"
    )
  end

  # Notifies business that customer approved the estimate
  def estimate_approved(estimate)
    @estimate = estimate
    @business = estimate.business

    # Get manager emails
    manager_emails = @business.users.where(role: :manager).pluck(:email)
    return mail(to: nil, subject: "Skip") if manager_emails.empty?

    mail(
      to: manager_emails,
      subject: "Estimate #{@estimate.estimate_number || "##{@estimate.id}"} Approved by Customer"
    )
  end

  # Notifies business that customer declined the estimate
  def estimate_declined(estimate)
    @estimate = estimate
    @business = estimate.business

    # Get manager emails
    manager_emails = @business.users.where(role: :manager).pluck(:email)
    return mail(to: nil, subject: "Skip") if manager_emails.empty?

    mail(
      to: manager_emails,
      subject: "Estimate #{@estimate.estimate_number || "##{@estimate.id}"} Declined by Customer"
    )
  end

  # Notifies business of requested changes
  def request_changes_notification(estimate, message)
    @estimate = estimate
    @business = estimate.business
    @message = message

    # Get manager emails
    manager_emails = @business.users.where(role: :manager).pluck(:email)
    return mail(to: nil, subject: "Skip") if manager_emails.empty?

    mail(
      to: manager_emails,
      subject: "Change Request for Estimate #{@estimate.estimate_number || "##{@estimate.id}"}"
    )
  end

  # Notifies customer when an estimate has been updated (versioned)
  def estimate_updated(estimate)
    @estimate = estimate
    @business = estimate.business
    @url = public_estimate_url(token: @estimate.token, host: "#{@business.subdomain}.#{Rails.application.config.main_domain}")

    # Attach updated PDF if available
    if @estimate.pdf.attached?
      filename = "#{@estimate.estimate_number || 'Estimate'}_v#{@estimate.current_version}.pdf"
      attachments[filename] = @estimate.pdf.download
    end

    mail(
      to: @estimate.customer_email,
      subject: "Updated Estimate #{@estimate.estimate_number || "##{@estimate.id}"} (Version #{@estimate.current_version})"
    )
  end

  # Confirms deposit payment was received
  def deposit_paid_confirmation(estimate)
    @estimate = estimate
    @business = estimate.business
    @booking = estimate.booking

    # Attach PDF with signature if available
    if @estimate.pdf.attached?
      attachments["#{@estimate.estimate_number || 'Estimate'}_Signed.pdf"] = @estimate.pdf.download
    end

    mail(
      to: @estimate.customer_email,
      subject: "Deposit Payment Confirmed - #{@business.name}"
    )
  end
end
