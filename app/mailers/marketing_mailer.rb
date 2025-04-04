class MarketingMailer < ApplicationMailer
  def campaign(recipient, campaign)
    # Placeholder for marketing campaign email
    @recipient = recipient
    @campaign = campaign
    mail(to: recipient.email, subject: campaign.subject)
  end

  def newsletter(recipient, newsletter)
    # Placeholder for newsletter email
    @recipient = recipient
    @newsletter = newsletter
    mail(to: recipient.email, subject: newsletter.subject)
  end

  def promotion(recipient, promotion)
    # Placeholder for promotion email
    @recipient = recipient
    @promotion = promotion
    mail(to: recipient.email, subject: promotion.subject)
  end
end
