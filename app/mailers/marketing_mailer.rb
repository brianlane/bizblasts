class MarketingMailer < ApplicationMailer
  def campaign(recipient, campaign)
    return unless recipient.can_receive_email?(:marketing)
    @recipient = recipient
    @campaign = campaign
    @support_email = ENV.fetch('SUPPORT_EMAIL', 'bizblaststeam@gmail.com')
    mail(to: recipient.email, subject: campaign.subject, reply_to: @support_email)
  end

  def newsletter(recipient, newsletter)
    return unless recipient.can_receive_email?(:marketing)
    @recipient = recipient
    @newsletter = newsletter
    @support_email = ENV.fetch('SUPPORT_EMAIL', 'bizblaststeam@gmail.com')
    mail(to: recipient.email, subject: newsletter.subject, reply_to: @support_email)
  end

  def promotion(recipient, promotion)
    return unless recipient.can_receive_email?(:marketing)
    @recipient = recipient
    @promotion = promotion
    @support_email = ENV.fetch('SUPPORT_EMAIL', 'bizblaststeam@gmail.com')
    mail(to: recipient.email, subject: promotion.subject, reply_to: @support_email)
  end
end
