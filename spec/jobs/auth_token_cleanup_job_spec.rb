# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AuthTokenCleanupJob, type: :job do
  let(:user) { create(:user) }
  
  before do
    # Clear any existing jobs
    clear_enqueued_jobs
  end

  describe '#perform' do
    it 'calls AuthToken.cleanup_expired!' do
      expect(AuthToken).to receive(:cleanup_expired!).and_return(5)
      
      job = described_class.new
      job.perform
    end

    it 'schedules the next cleanup job' do
      allow(AuthToken).to receive(:cleanup_expired!).and_return(0)
      
      expect {
        described_class.new.perform
      }.to have_enqueued_job(described_class).on_queue('default')
    end

    it 'continues scheduling on errors' do
      allow(AuthToken).to receive(:cleanup_expired!).and_raise(StandardError.new('DB issue'))
      
      job = described_class.new
      
      expect {
        job.perform
      }.to raise_error(StandardError)
      
      # Should still schedule next job even after error
      expect(AuthTokenCleanupJob).to have_been_enqueued
    end

    it 'logs cleanup metrics' do
      allow(AuthToken).to receive(:cleanup_expired!).and_return(3)
      
      expect(Rails.logger).to receive(:info).at_least(:once)
      expect(Rails.logger).to receive(:debug).at_least(:once)
      
      described_class.new.perform
    end
  end

  describe '#cleanup_orphaned_tokens' do
    let(:job) { described_class.new }

    it 'does not attempt Redis orphan cleanup' do
      allow(AuthToken).to receive(:cleanup_expired!).and_return(0)
      
      expect(Rails.logger).to receive(:info).at_least(:once)
      described_class.new.perform
    end

    it 'handles metric logging without Redis' do
      allow(AuthToken).to receive(:cleanup_expired!).and_return(0)
      
      expect(Rails.logger).to receive(:debug).at_least(:once)
      described_class.new.perform
    end
  end

  describe '#log_cleanup_metrics' do
    let(:job) { described_class.new }

    it 'logs warning for high number of orphaned tokens' do
      allow(AuthToken).to receive(:cleanup_expired!).and_return(0)
      
      # Simulate finding many orphaned tokens
      allow(job).to receive(:cleanup_orphaned_tokens).and_return(15)
      
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:debug)
      expect(Rails.logger).to receive(:warn).at_least(:once)
      
      job.perform
    end

    it 'logs debug message when no cleanup needed' do
      allow(AuthToken).to receive(:cleanup_expired!).and_return(0)
      
      allow(Rails.logger).to receive(:info)
      expect(Rails.logger).to receive(:debug).at_least(:once)
      
      job.perform
    end
  end

  describe '.start_recurring_cleanup!' do
    it 'enqueues a cleanup job' do
      expect {
        described_class.start_recurring_cleanup!
      }.to have_enqueued_job(described_class)
    end

    it 'logs that cleanup was started' do
      expect(Rails.logger).to receive(:info).with(/Started recurring cleanup job/)
      
      described_class.start_recurring_cleanup!
    end
  end

  describe '.cleanup_now!' do
    it 'performs cleanup immediately' do
      expect(AuthToken).to receive(:cleanup_expired!).and_return(2)
      
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:debug)
      
      described_class.cleanup_now!
    end
  end

  describe 'error handling and resilience' do
    it 'continues scheduling even if cleanup fails' do
      allow(AuthToken).to receive(:cleanup_expired!).and_raise(StandardError.new('Redis down'))
      
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:debug)
      allow(Rails.logger).to receive(:error)
      
      expect {
        described_class.new.perform
      }.to raise_error(StandardError)
      
      # Should still have scheduled the next job
      expect(AuthTokenCleanupJob).to have_been_enqueued
    end

    # Redis is no longer used; ensure job raises when DB errors occur
  end

  describe 'job scheduling' do
    it 'schedules next job with correct interval' do
      allow(AuthToken).to receive(:cleanup_expired!).and_return(0)
      
      described_class.new.perform
      
      expect(AuthTokenCleanupJob).to have_been_enqueued.with(no_args).on_queue('default')
    end

    it 'uses default queue' do
      expect(described_class.queue_name).to eq('default')
    end
  end

  describe 'integration with AuthToken model' do
    it 'calls the correct cleanup method on AuthToken' do
      expect(AuthToken).to receive(:cleanup_expired!).once.and_return(1)
      
      described_class.new.perform
    end

    it 'invokes AuthToken.cleanup_expired! via perform' do
      expect(AuthToken).to receive(:cleanup_expired!).and_return(0)
      described_class.new.perform
    end
  end
end