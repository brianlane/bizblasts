# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MarketingCampaignJob, type: :job do
  let(:business) { create(:business) }
  let(:campaign) { create(:marketing_campaign, business: business, campaign_type: 'email') }
  
  before do
    ActsAsTenant.current_tenant = business
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe '#perform' do
    context 'with email campaign' do
      it 'processes email campaign without error' do
        # Create a tenant customer that can receive marketing emails
        customer = create(:tenant_customer, business: business, email_marketing_opt_out: false)
        
        # Mock the campaign to be in running status
        allow(campaign).to receive(:running?).and_return(true)
        allow(campaign).to receive(:complete!).and_return(true)
        
        # This should not raise a NoMethodError
        expect {
          MarketingCampaignJob.perform_now(campaign.id)
        }.not_to raise_error
      end

      it 'filters out customers who cannot receive marketing emails' do
        # Create customers with different email preferences
        customer1 = create(:tenant_customer, business: business, email_marketing_opt_out: false)
        customer2 = create(:tenant_customer, business: business, email_marketing_opt_out: true)
        customer3 = create(:tenant_customer, business: business, unsubscribed_at: Time.current)
        
        # Mock the campaign to be in running status
        allow(campaign).to receive(:running?).and_return(true)
        allow(campaign).to receive(:complete!).and_return(true)
        
        # Mock the get_recipients method to return our test customers
        allow_any_instance_of(MarketingCampaignJob).to receive(:get_recipients).and_return([customer1, customer2, customer3])
        
        # Mock the update_campaign_metrics method
        allow_any_instance_of(MarketingCampaignJob).to receive(:update_campaign_metrics)
        
        # Perform the job
        MarketingCampaignJob.perform_now(campaign.id)
        
        # Verify that only customer1 can receive marketing emails
        expect(customer1.can_receive_email?(:marketing)).to be true
        expect(customer2.can_receive_email?(:marketing)).to be false
        expect(customer3.can_receive_email?(:marketing)).to be false
      end
    end
  end
end 