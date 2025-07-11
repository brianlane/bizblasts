class MarketingMailer < ApplicationMailer
  def campaign(recipient, campaign)
    return unless recipient.can_receive_email?(:marketing)
    @recipient = recipient
    @campaign = campaign
    mail(to: recipient.email, subject: campaign.subject)
  end

  def newsletter(recipient, newsletter)
    return unless recipient.can_receive_email?(:marketing)
    @recipient = recipient
    @newsletter = newsletter
    mail(to: recipient.email, subject: newsletter.subject)
  end

  def promotion(recipient, promotion)
    return unless recipient.can_receive_email?(:marketing)
    @recipient = recipient
    @promotion = promotion
    mail(to: recipient.email, subject: promotion.subject)
  end
end
