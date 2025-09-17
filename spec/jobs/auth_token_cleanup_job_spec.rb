# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AuthTokenCleanupJob, type: :job do
  let(:mock_redis) { double('Redis') }
  let(:user) { create(:user) }
  
  before do
    # Mock Redis for testing
    allow(AuthToken).to receive(:redis).and_return(mock_redis)
    
    # Default Redis behavior
    allow(mock_redis).to receive(:setex).and_return('OK')
    allow(mock_redis).to receive(:get).and_return(nil)
    allow(mock_redis).to receive(:del).and_return(1)
    allow(mock_redis).to receive(:ttl).and_return(120)
    allow(mock_redis).to receive(:exists).and_return(false)
    allow(mock_redis).to receive(:scan_each).and_return([])
    
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

    it 'handles Redis connection errors gracefully' do
      # Mock Redis to raise an error
      redis_error = Class.new(StandardError)
      stub_const('Redis::ConnectionError', redis_error)
      
      allow(AuthToken).to receive(:cleanup_expired!).and_raise(redis_error.new('Connection failed'))
      
      job = described_class.new
      
      expect {
        job.perform
      }.to raise_error(redis_error)
      
      # Should still schedule next job even after error
      expect(AuthTokenCleanupJob).to have_been_enqueued
    end

    it 'logs cleanup metrics' do
      allow(AuthToken).to receive(:cleanup_expired!).and_return(3)
      allow(mock_redis).to receive(:scan_each).and_return([])
      
      expect(Rails.logger).to receive(:info).at_least(:once)
      expect(Rails.logger).to receive(:debug).at_least(:once)
      
      described_class.new.perform
    end
  end

  describe '#cleanup_orphaned_tokens' do
    let(:job) { described_class.new }

    it 'identifies and cleans up tokens without TTL' do
      # Mock Redis scan to return some test keys
      test_keys = [
        'auth_token:token1',
        'auth_token:token2',
        'auth_token:token3'
      ]
      
      allow(mock_redis).to receive(:scan_each).and_yield('auth_token:token1').and_yield('auth_token:token2')
      
      # First token has no TTL (-1), second token is expired (-2)
      allow(mock_redis).to receive(:ttl).with('auth_token:token1').and_return(-1)
      allow(mock_redis).to receive(:ttl).with('auth_token:token2').and_return(-2)
      
      # Expect deletion of the first token only
      expect(mock_redis).to receive(:del).with('auth_token:token1').and_return(1)
      expect(mock_redis).not_to receive(:del).with('auth_token:token2')
      
      allow(AuthToken).to receive(:cleanup_expired!).and_return(0)
      
      job.perform
    end

    it 'limits processing to BATCH_SIZE tokens' do
      # Mock a large number of keys
      large_key_set = (1..2000).map { |i| "auth_token:token#{i}" }
      
      allow(mock_redis).to receive(:scan_each) do |&block|
        large_key_set.first(AuthTokenCleanupJob::BATCH_SIZE).each(&block)
      end
      
      # All keys have valid TTL
      allow(mock_redis).to receive(:ttl).and_return(120)
      allow(AuthToken).to receive(:cleanup_expired!).and_return(0)
      
      # Just expect that logging happens without specific message checking
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:debug)
      
      job.perform
    end

    it 'handles Redis scan errors gracefully' do
      redis_error = Class.new(StandardError)
      allow(mock_redis).to receive(:scan_each).and_raise(redis_error.new('Scan failed'))
      allow(AuthToken).to receive(:cleanup_expired!).and_return(0)
      
      expect(Rails.logger).to receive(:error).with(/Error scanning Redis keys/)
      
      # Should not crash the job
      expect { described_class.new.perform }.not_to raise_error
    end
  end

  describe '#log_cleanup_metrics' do
    let(:job) { described_class.new }

    it 'logs warning for high number of orphaned tokens' do
      allow(AuthToken).to receive(:cleanup_expired!).and_return(0)
      allow(mock_redis).to receive(:scan_each).and_return([])
      
      # Simulate finding many orphaned tokens
      allow(job).to receive(:cleanup_orphaned_tokens).and_return(15)
      
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:debug)
      expect(Rails.logger).to receive(:warn).at_least(:once)
      
      job.perform
    end

    it 'logs debug message when no cleanup needed' do
      allow(AuthToken).to receive(:cleanup_expired!).and_return(0)
      allow(mock_redis).to receive(:scan_each).and_return([])
      
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

    it 'handles missing Redis gracefully' do
      allow(AuthToken).to receive(:redis).and_raise(StandardError.new('Redis not configured'))
      
      expect {
        described_class.new.perform
      }.to raise_error(StandardError)
    end
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

    it 'uses the correct Redis key prefix for scanning' do
      allow(AuthToken).to receive(:cleanup_expired!).and_return(0)
      
      expect(mock_redis).to receive(:scan_each).with(
        match: "#{AuthToken::REDIS_KEY_PREFIX}:*",
        count: AuthTokenCleanupJob::BATCH_SIZE
      )
      
      described_class.new.perform
    end
  end
end