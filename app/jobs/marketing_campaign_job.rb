class MarketingCampaignJob < ApplicationJob
  queue_as :marketing

  def perform(campaign_id, options = {})
    # Find the campaign
    campaign = MarketingCampaign.find_by(id: campaign_id)
    return unless campaign
    
    # Skip if campaign is not in running status
    return unless campaign.running?
    
    # Process the campaign based on its type
    case campaign.campaign_type
    when 'email'
      process_email_campaign(campaign, options)
    when 'sms'
      process_sms_campaign(campaign, options)
    when 'combined'
      process_email_campaign(campaign, options)
      process_sms_campaign(campaign, options)
    end
    
    # Update campaign status
    campaign.complete!
    
    # Log completion
    Rails.logger.info "Marketing campaign ##{campaign.id} completed at #{Time.current}"
  end
  
  private
  
  def process_email_campaign(campaign, options)
    # Get recipients based on segmentation
    recipients = get_recipients(campaign, options)
    return if recipients.empty?
    
    # In a real implementation, this would use ActionMailer or a third-party service
    # recipients.each do |recipient|
    #   MarketingMailer.campaign_email(recipient, campaign).deliver_later
    # end
    
    # Log the count of emails sent
    recipient_count = recipients.count
    Rails.logger.info "Sending #{recipient_count} emails for campaign ##{campaign.id}"
    
    # Record metrics
    update_campaign_metrics(campaign, { email_recipients_count: recipient_count, email_sent_at: Time.current })
  end
  
  def process_sms_campaign(campaign, options)
    # Get recipients based on segmentation
    recipients = get_recipients(campaign, options)
    return if recipients.empty?
    
    # Filter recipients who have phone numbers
    recipients_with_phones = recipients.select { |r| r.phone.present? }
    return if recipients_with_phones.empty?
    
    # Send SMS to each recipient
    recipients_with_phones.each do |recipient|
      SmsService.send_message(
        recipient.phone,
        campaign.content || "Check out our latest offers!",
        {
          customer_id: recipient.id,
          marketing_campaign_id: campaign.id,
          business_id: campaign.business_id
        }
      )
    end
    
    # Log the count of SMS sent
    recipient_count = recipients_with_phones.count
    Rails.logger.info "Sending #{recipient_count} SMS for campaign ##{campaign.id}"
    
    # Record metrics
    update_campaign_metrics(campaign, { sms_recipients_count: recipient_count, sms_sent_at: Time.current })
  end
  
  def get_recipients(campaign, options)
    # This would normally use sophisticated segmentation logic
    # based on the campaign settings
    
    # For this placeholder implementation, just get active customers
    # with email addresses for the campaign's business
    Customer.where(business_id: campaign.business_id, active: true)
            .where.not(email: nil)
            .limit(50) # Limit for safety in development
  end
  
  def update_campaign_metrics(campaign, metrics)
    # Update the campaign with metrics
    campaign_metrics = campaign.metadata || {}
    campaign.update(metadata: campaign_metrics.merge(metrics))
  end
end
