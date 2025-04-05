# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MarketingService, type: :service do
  include ActiveJob::TestHelper # For MarketingCampaignJob

  let!(:tenant) { create(:business) }

  around do |example|
    ActsAsTenant.with_tenant(tenant) do
      clear_enqueued_jobs
      example.run
      clear_enqueued_jobs 
    end
  end

  describe '.create_campaign' do
    let(:valid_params) do 
      # Build params from factory attributes, ensuring business_id is set
      attributes = attributes_for(:marketing_campaign, :scheduled_past) # Schedule in past for immediate execution test
      attributes.merge(business_id: tenant.id)
    end

    context 'with valid parameters' do
      it 'creates a new MarketingCampaign' do
        expect {
          campaign, errors = described_class.create_campaign(valid_params)
          expect(errors).to be_nil
          expect(campaign).to be_persisted
          expect(campaign.name).to eq(valid_params[:name])
        }.to change(MarketingCampaign, :count).by(1)
      end
      
      context 'when scheduled_at is in the past' do
        it 'changes the campaign status to running' do
          campaign, _ = described_class.create_campaign(valid_params) 
          expect(campaign.reload.status).to eq('running')
        end
        
        it 'enqueues a MarketingCampaignJob' do
          expect {
            described_class.create_campaign(valid_params)
          }.to have_enqueued_job(MarketingCampaignJob)
        end
      end
      
      context 'when scheduled_at is in the future' do
         let(:future_params) do
           attributes = attributes_for(:marketing_campaign) # Default is future
           attributes.merge(business_id: tenant.id)
         end
         
         it 'keeps the campaign status as scheduled' do
           campaign, _ = described_class.create_campaign(future_params)
           expect(campaign.reload.status).to eq('scheduled')
         end
         
         it 'does not enqueue a MarketingCampaignJob immediately' do
           expect {
             described_class.create_campaign(future_params)
           }.not_to have_enqueued_job(MarketingCampaignJob)
         end
      end
    end

    context 'with invalid parameters' do
      let(:invalid_params) { valid_params.except(:name) }
      
      it 'does not create a campaign' do
        expect {
          campaign, errors = described_class.create_campaign(invalid_params)
          expect(campaign).to be_nil
          expect(errors).not_to be_nil
          expect(errors[:name]).to include("can't be blank")
        }.not_to change(MarketingCampaign, :count)
      end
      
      it 'does not enqueue any jobs' do
        expect {
          described_class.create_campaign(invalid_params)
        }.not_to have_enqueued_job(MarketingCampaignJob)
      end
    end
  end
  
  describe '.execute_campaign' do
    let!(:scheduled_campaign) { create(:marketing_campaign, :scheduled, name: "Scheduled Email Campaign", business: tenant) }
    let!(:draft_campaign) { create(:marketing_campaign, :draft, name: "Draft Campaign", business: tenant) }
    let!(:sms_campaign) { create(:marketing_campaign, :sms, :scheduled, name: "Scheduled SMS Campaign", business: tenant) }

    context 'with a scheduled campaign' do
      before do
        # Prevent actual job execution during test, just check enqueueing
        allow(MarketingCampaignJob).to receive(:perform_later)
        # Mock private send methods to avoid external calls/placeholders
        allow(described_class).to receive(:send_email_campaign) 
        allow(described_class).to receive(:send_sms_campaign)
        # Mock complete! as execute_campaign calls it
        allow(scheduled_campaign).to receive(:complete!) 
      end
      
      it 'updates the campaign status to running' do
        described_class.execute_campaign(scheduled_campaign)
        expect(scheduled_campaign.reload.status).to eq('running')
        expect(scheduled_campaign.started_at).to be_present
      end
      
      it 'calls the correct send method based on type (email)' do
        expect(described_class).to receive(:send_email_campaign).with(scheduled_campaign)
        expect(described_class).not_to receive(:send_sms_campaign)
        described_class.execute_campaign(scheduled_campaign)
      end

      it 'calls the correct send method based on type (sms)' do
        allow(sms_campaign).to receive(:complete!) # Mock complete for this campaign too
        expect(described_class).to receive(:send_sms_campaign).with(sms_campaign)
        expect(described_class).not_to receive(:send_email_campaign)
        described_class.execute_campaign(sms_campaign)
      end

      it 'calls complete! on the campaign' do
        expect(scheduled_campaign).to receive(:complete!)
        described_class.execute_campaign(scheduled_campaign)
      end
      
      # Note: execute! method in the model actually enqueues the job.
      # The service itself doesn't enqueue directly. Testing execute! behaviour
      # belongs in the model spec.
    end

    context 'with a non-scheduled campaign' do
      it 'returns an error and does not change status' do
        campaign, error = described_class.execute_campaign(draft_campaign)
        expect(campaign).to be_nil
        expect(error).to eq("Campaign is not in scheduled status")
        expect(draft_campaign.reload.status).to eq('draft')
      end
      
      it 'does not call send methods or complete!' do
         expect(described_class).not_to receive(:send_email_campaign)
         expect(described_class).not_to receive(:send_sms_campaign)
         expect(draft_campaign).not_to receive(:complete!)
         described_class.execute_campaign(draft_campaign)
      end
    end
  end

  describe '.cancel_campaign' do
    let!(:scheduled_campaign_to_cancel) { create(:marketing_campaign, :scheduled, name: "Cancel Me Scheduled", business: tenant) }
    let!(:running_campaign_to_cancel) { create(:marketing_campaign, :running, name: "Cancel Me Running", business: tenant) }
    let!(:completed_campaign) { create(:marketing_campaign, :completed, name: "Already Completed", business: tenant) }

    context 'when campaign is scheduled' do
      it 'updates status to cancelled' do
        campaign, error = described_class.cancel_campaign(scheduled_campaign_to_cancel)
        expect(error).to be_nil
        expect(campaign).to eq(scheduled_campaign_to_cancel)
        expect(campaign.reload.status).to eq('cancelled')
      end
    end

    context 'when campaign is running' do
      it 'updates status to cancelled' do
        campaign, error = described_class.cancel_campaign(running_campaign_to_cancel)
        expect(error).to be_nil
        expect(campaign).to eq(running_campaign_to_cancel)
        expect(campaign.reload.status).to eq('cancelled')
      end
    end

    context 'when campaign cannot be cancelled (e.g., completed)' do
      it 'returns an error and does not change status' do
        campaign, error = described_class.cancel_campaign(completed_campaign)
        expect(campaign).to be_nil
        expect(error).to eq("Campaign cannot be cancelled")
        expect(completed_campaign.reload.status).to eq('completed')
      end
    end
  end
  
  describe '.get_campaign_metrics' do
    let!(:email_campaign) { create(:marketing_campaign, :completed, name: "Metrics Email", business: tenant) }
    let!(:sms_campaign_metrics) { create(:marketing_campaign, :sms, :completed, name: "Metrics SMS", business: tenant) }
    
    before do
      # Remove business: tenant from create_list calls
      create_list(:sms_message, 5, :sent, marketing_campaign: sms_campaign_metrics)
      create_list(:sms_message, 10, :delivered, marketing_campaign: sms_campaign_metrics)
      create_list(:sms_message, 2, :failed, marketing_campaign: sms_campaign_metrics)
      # Note: The service currently uses rand() for email/combined metrics, so testing precise values is difficult
    end

    context 'for an email campaign' do
      it 'returns placeholder email metrics' do
        metrics = described_class.get_campaign_metrics(email_campaign)
        expect(metrics).to include(:sent, :opened, :clicked, :bounced, :unsubscribed)
        # Check types or ranges due to randomness
        expect(metrics[:sent]).to be_a(Integer)
      end
    end

    context 'for an SMS campaign' do
      it 'returns metrics based on associated SmsMessages' do
        metrics = described_class.get_campaign_metrics(sms_campaign_metrics)
        expect(metrics).to include(:sent, :delivered, :failed, :response_rate)
        expect(metrics[:sent]).to eq(5) # 5 created with :sent status
        expect(metrics[:delivered]).to eq(10)
        expect(metrics[:failed]).to eq(2)
        expect(metrics[:response_rate]).to be_between(0, 30) # Checks the random range
      end
    end

    context 'for a combined campaign' do
      let!(:combined_campaign) { create(:marketing_campaign, :combined, :completed, name: "Metrics Combined", business: tenant) }
      before do
         # Remove business: tenant from create_list call
         create_list(:sms_message, 7, :delivered, marketing_campaign: combined_campaign)
      end
      
      it 'returns combined placeholder metrics' do
        metrics = described_class.get_campaign_metrics(combined_campaign)
        expect(metrics).to include(:email_sent, :email_opened, :sms_sent, :sms_delivered)
        expect(metrics[:email_sent]).to be_a(Integer)
        # Sms count should be 0 unless we change the test setup to add sent/failed too
        expect(metrics[:sms_sent]).to eq(0) # 7 created were :delivered 
        expect(metrics[:sms_delivered]).to eq(7)
      end
    end
  end

  describe '.segment_customers' do
    let!(:customer1) { create(:tenant_customer, name: "Recent Booker", business: tenant) }
    let!(:customer2) { create(:tenant_customer, name: "Old Booker", business: tenant) }
    let!(:customer3) { create(:tenant_customer, name: "Non Booker", business: tenant) }
    let!(:service_a) { create(:service, name: "Service A", business: tenant) }
    let!(:service_b) { create(:service, name: "Service B", business: tenant) }
    let!(:staff1) { create(:staff_member, name: "Staff One", business: tenant) }
    let!(:staff2) { create(:staff_member, name: "Staff Two", business: tenant) }
    
    before do
      # Use different staff members to avoid conflicts
      create(:booking, tenant_customer: customer1, service: service_a, staff_member: staff1, start_time: 10.days.ago, business: tenant)
      create(:booking, tenant_customer: customer2, service: service_b, staff_member: staff2, start_time: 40.days.ago, business: tenant)
    end

    context 'with :has_booking_in_last_days filter' do
      it 'returns customers with recent bookings' do
        segmented = described_class.segment_customers(tenant.id, { has_booking_in_last_days: 15 })
        expect(segmented).to contain_exactly(customer1)
      end
      
      it 'returns no customers if threshold is too short' do
         segmented = described_class.segment_customers(tenant.id, { has_booking_in_last_days: 5 })
         expect(segmented).to be_empty
      end
    end

    context 'with :service_id filter' do
      it 'returns customers who booked a specific service' do
        segmented = described_class.segment_customers(tenant.id, { service_id: service_a.id })
        expect(segmented).to contain_exactly(customer1)
        
        segmented = described_class.segment_customers(tenant.id, { service_id: service_b.id })
        expect(segmented).to contain_exactly(customer2)
      end
    end

    context 'with :no_booking_in_last_days filter' do
      it 'returns customers without recent bookings' do
        # Customers 2 and 3 have no bookings in last 15 days
        segmented = described_class.segment_customers(tenant.id, { no_booking_in_last_days: 15 })
        expect(segmented).to contain_exactly(customer2, customer3)
      end
    end
    
    context 'with combined filters' do
       it 'returns customers matching all criteria' do
         # Customer who booked Service A but not in the last 15 days (no one)
         segmented = described_class.segment_customers(tenant.id, { service_id: service_a.id, no_booking_in_last_days: 15 })
         expect(segmented).to be_empty
         
         # Customer who booked Service B and has a booking in last 50 days (customer2)
         segmented = described_class.segment_customers(tenant.id, { service_id: service_b.id, has_booking_in_last_days: 50 })
         expect(segmented).to contain_exactly(customer2)
       end
    end
    
    it 'returns all active customers if no filters provided' do
       segmented = described_class.segment_customers(tenant.id, {})
       expect(segmented).to contain_exactly(customer1, customer2, customer3)
    end
  end

  # TODO: Add tests for segment_customers
end 