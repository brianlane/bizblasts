require 'rails_helper'

RSpec.describe MarketingMailer, type: :mailer do
  let(:user) { create(:user, email: 'marketinguser@example.com') }
  let(:campaign) { double('Campaign', subject: 'Test Campaign') }
  let(:newsletter) { double('Newsletter', subject: 'Test Newsletter') }
  let(:promotion) { double('Promotion', subject: 'Test Promotion') }

  it 'does not send marketing emails if user is globally unsubscribed' do
    user.update!(unsubscribed_at: Time.current)
    
    # Clear any existing deliveries
    ActionMailer::Base.deliveries.clear
    
    # Call the mailer methods
    MarketingMailer.campaign(user, campaign).deliver_now
    MarketingMailer.newsletter(user, newsletter).deliver_now
    MarketingMailer.promotion(user, promotion).deliver_now
    
    # Verify no emails were actually delivered
    expect(ActionMailer::Base.deliveries.count).to eq(0)
  end
end 