# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DomainMonitoringJob, type: :job do
  include ActiveJob::TestHelper

  let!(:business) do
    create(:business,
      host_type: 'custom_domain',
      hostname: 'example.com',
      status: 'cname_monitoring',
      cname_monitoring_active: true,
      cname_check_attempts: 2
    )
  end

  let(:monitoring_service) { instance_double(DomainMonitoringService) }

  before do
    allow(DomainMonitoringService).to receive(:new).and_return(monitoring_service)
  end

  describe '#perform' do
    context 'with valid business' do
      let(:check_result) do
        {
          success: true,
          verified: false,
          should_continue: true,
          attempts: 3,
          max_attempts: 12
        }
      end

      before do
        allow(monitoring_service).to receive(:perform_check!).and_return(check_result)
        allow(business).to receive(:cname_due_for_check?).and_return(true)
        allow(Business).to receive(:find).with(business.id).and_return(business)
      end

      it 'performs monitoring check' do
        expect(monitoring_service).to receive(:perform_check!)

        described_class.perform_now(business.id)
      end

      it 'schedules next check when monitoring should continue' do
        expect(described_class).to receive_message_chain(:set, :perform_later).with(wait: 5.minutes).with(business.id)

        described_class.perform_now(business.id)
      end

      context 'when verification is complete' do
        let(:check_result) do
          {
            success: true,
            verified: true,
            should_continue: false,
            attempts: 5,
            max_attempts: 12
          }
        end

        it 'does not schedule next check' do
          allow(Business).to receive(:find).with(business.id).and_return(business)
          expect(described_class).not_to receive(:set)

          described_class.perform_now(business.id)
        end
      end

      context 'when monitoring times out' do
        let(:check_result) do
          {
            success: true,
            verified: false,
            should_continue: false,
            attempts: 12,
            max_attempts: 12
          }
        end

        it 'does not schedule next check' do
          allow(Business).to receive(:find).with(business.id).and_return(business)
          expect(described_class).not_to receive(:set)

          described_class.perform_now(business.id)
        end
      end
    end

    context 'with non-existent business' do
      it 'handles gracefully without error' do
        expect { described_class.perform_now(999999) }.not_to raise_error
      end

      it 'logs error message' do
        expect(Rails.logger).to receive(:error).with(/Business 999999 not found/)

        described_class.perform_now(999999)
      end
    end

    context 'when business is not due for check' do
      before do
        business.update!(updated_at: 2.minutes.ago)
        allow(business).to receive(:cname_due_for_check?).and_return(false)
        allow(Business).to receive(:find).with(business.id).and_return(business)
      end

      it 'schedules next check without performing monitoring' do
        expect(monitoring_service).not_to receive(:perform_check!)
        expect(described_class).to receive_message_chain(:set, :perform_later).with(wait: 5.minutes).with(business.id)

        described_class.perform_now(business.id)
      end
    end

    context 'when monitoring is no longer needed' do
      before do
        business.update!(status: 'cname_active', cname_monitoring_active: false)
      end

      it 'skips monitoring without scheduling next check' do
        expect(monitoring_service).not_to receive(:perform_check!)
        expect(described_class).not_to receive(:set)

        described_class.perform_now(business.id)
      end
    end

    context 'when monitoring service raises error' do
      before do
        allow(monitoring_service).to receive(:perform_check!).and_raise(StandardError.new('Monitoring failed'))
        allow(business).to receive(:cname_due_for_check?).and_return(true)
        allow(Business).to receive(:find).with(business.id).and_return(business)
        business.update!(
          status: 'cname_monitoring',
          cname_monitoring_active: true,
          host_type: 'custom_domain',
          hostname: 'example.com',
          cname_check_attempts: 1
        )
      end

      it 'does not schedule next check and swallows error due to retry_on' do
        expect(DomainMonitoringJob).not_to receive(:set)
        expect { described_class.perform_now(business.id) }.not_to raise_error
      end

      it 'does not raise error after retries are handled' do
        expect { described_class.perform_now(business.id) }.not_to raise_error
      end
    end
  end

  describe '.start_monitoring' do
    it 'queues monitoring job for business' do
      expect { described_class.start_monitoring(business.id) }.to have_enqueued_job(described_class).with(business.id)
    end
  end

  describe '.stop_monitoring' do
    it 'stops monitoring for business' do
      described_class.stop_monitoring(business.id)

      business.reload
      expect(business.cname_monitoring_active).to be false
    end

    it 'handles non-existent business gracefully' do
      expect { described_class.stop_monitoring(999999) }.not_to raise_error
    end
  end

  describe '.monitor_all_pending' do
    let!(:monitoring_business1) do
      create(:business,
        host_type: 'custom_domain',
        status: 'cname_monitoring',
        cname_monitoring_active: true,
        cname_check_attempts: 5,
        updated_at: 10.minutes.ago
      )
    end

    let!(:monitoring_business2) do
      create(:business,
        host_type: 'custom_domain',
        status: 'cname_monitoring',
        cname_monitoring_active: true,
        cname_check_attempts: 8,
        updated_at: 7.minutes.ago
      )
    end

    let!(:recent_business) do
      create(:business,
        host_type: 'custom_domain',
        status: 'cname_monitoring',
        cname_monitoring_active: true,
        cname_check_attempts: 2,
        updated_at: 2.minutes.ago
      )
    end

    let!(:inactive_business) do
      create(:business,
        host_type: 'custom_domain',
        status: 'cname_monitoring',
        cname_monitoring_active: false,
        updated_at: 10.minutes.ago
      )
    end

    let!(:completed_business) do
      create(:business,
        host_type: 'custom_domain',
        status: 'cname_monitoring',
        cname_monitoring_active: true,
        cname_check_attempts: 12,
        updated_at: 10.minutes.ago
      )
    end

    it 'queues jobs for businesses needing monitoring' do
      expect { described_class.monitor_all_pending }.to have_enqueued_job(described_class)
        .with(monitoring_business1.id)
        .and have_enqueued_job(described_class)
        .with(monitoring_business2.id)
    end

    it 'does not queue jobs for recent updates' do
      expect { described_class.monitor_all_pending }.not_to have_enqueued_job(described_class)
        .with(recent_business.id)
    end

    it 'does not queue jobs for inactive monitoring' do
      expect { described_class.monitor_all_pending }.not_to have_enqueued_job(described_class)
        .with(inactive_business.id)
    end

    it 'does not queue jobs for completed monitoring' do
      expect { described_class.monitor_all_pending }.not_to have_enqueued_job(described_class)
        .with(completed_business.id)
    end
  end

  describe 'private methods' do
    describe '#should_continue_monitoring?' do
      let(:job) { described_class.new }

      it 'returns true for valid monitoring business' do
        expect(job.send(:should_continue_monitoring?, business)).to be true
      end

      it 'returns false for non-monitoring status' do
        business.update!(status: 'active')
        expect(job.send(:should_continue_monitoring?, business)).to be false
      end

      it 'returns false for inactive monitoring' do
        business.update!(cname_monitoring_active: false)
        expect(job.send(:should_continue_monitoring?, business)).to be false
      end

      it 'returns false for exceeded attempts' do
        business.update!(cname_check_attempts: 12)
        expect(job.send(:should_continue_monitoring?, business)).to be false
      end

      it 'returns false for non-custom domain' do
        business.update!(host_type: 'subdomain', hostname: 'example')
        expect(job.send(:should_continue_monitoring?, business)).to be false
      end
    end
  end
end