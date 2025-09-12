# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CertificatePropagationRetryJob, type: :job do
  include ActiveJob::TestHelper

  let!(:business) do
    create(:business,
      tier: 'premium',
      host_type: 'custom_domain',
      hostname: 'example.com',
      status: 'cname_active',
      canonical_preference: 'apex',
      render_domain_added: true
    )
  end

  let(:render_service) { instance_double(RenderDomainService) }
  let(:health_checker) { instance_double(DomainHealthChecker) }
  let(:apex_domain_data) { { 'id' => 'apex-domain-id', 'name' => 'example.com' } }
  let(:www_domain_data) { { 'id' => 'www-domain-id', 'name' => 'www.example.com' } }

  before do
    allow(RenderDomainService).to receive(:new).and_return(render_service)
    allow(DomainHealthChecker).to receive(:new).and_return(health_checker)
    allow(Business).to receive(:find).with(business.id).and_return(business)
    # Mock job scheduling
    allow(RenderDomainVerificationJob).to receive(:perform_later)
    allow(RenderDomainVerificationJob).to receive_message_chain(:set, :perform_later)
    allow(DomainRebuildContinueJob).to receive_message_chain(:set, :perform_later)
  end

  describe '#perform' do
    context 'when business should continue retrying' do
      before do
        allow(health_checker).to receive(:check_health).and_return({ healthy: false, ssl_ready: false })
        allow(render_service).to receive(:find_domain_by_name).with('example.com').and_return(apex_domain_data)
        allow(render_service).to receive(:find_domain_by_name).with('www.example.com').and_return(www_domain_data)
        allow(render_service).to receive(:verify_domain)
      end

      context 'for retries 0-2' do
        it 'schedules verification jobs without rebuilding domains' do
          expect(RenderDomainVerificationJob).to receive(:perform_later).with('example.com')
          expect(RenderDomainVerificationJob).to receive_message_chain(:set, :perform_later)
            .with(wait: 30.seconds).with('www.example.com')
          expect(render_service).not_to receive(:remove_domain)
          expect(render_service).not_to receive(:add_domain)

          described_class.perform_now(business.id, 2) # Third retry (0-based)
        end

        it 'schedules next retry' do
          expect(described_class).to receive_message_chain(:set, :perform_later)
            .with(wait: 20.minutes).with(business.id, 3)

          described_class.perform_now(business.id, 2)
        end
      end

      context 'for retry 3 and beyond (domain rebuild)' do
        before do
          allow(render_service).to receive(:remove_domain)
          allow(render_service).to receive(:add_domain)
        end

        it 'starts domain rebuild by removing domains and scheduling continue job' do
          # Expect removal of both domains
          expect(render_service).to receive(:remove_domain).with('apex-domain-id')
          expect(render_service).to receive(:remove_domain).with('www-domain-id')

          # Expect scheduling of continue job after 10 seconds
          expect(DomainRebuildContinueJob).to receive_message_chain(:set, :perform_later)
            .with(wait: 10.seconds).with(business.id)

          described_class.perform_now(business.id, 3)
        end

        it 'schedules next retry after rebuild' do
          expect(described_class).to receive_message_chain(:set, :perform_later)
            .with(wait: 30.minutes).with(business.id, 4)

          described_class.perform_now(business.id, 3)
        end
      end

      context 'when SSL starts working during retry' do
        before do
          allow(health_checker).to receive(:check_health).and_return({ healthy: true, ssl_ready: true })
        end

        it 'stops retrying without triggering verification' do
          expect(render_service).not_to receive(:verify_domain)
          expect(described_class).not_to receive(:set)

          described_class.perform_now(business.id, 2)
        end

        it 'logs success message' do
          expect(Rails.logger).to receive(:info).with(/Retry attempt/)
          expect(Rails.logger).to receive(:info)
            .with("[CertificatePropagationRetryJob] SSL now working for example.com, stopping retries")

          described_class.perform_now(business.id, 2)
        end
      end

      context 'when at max retries (should stop immediately)' do
        it 'does not schedule next retry' do
          expect(described_class).not_to receive(:set)

          described_class.perform_now(business.id, 6) # Equals max_retry_attempts, should stop immediately
        end

        it 'logs stop message' do
          expect(Rails.logger).to receive(:info).with(/Retry attempt/)
          expect(Rails.logger).to receive(:info).with(/Stopping retries for business/)

          described_class.perform_now(business.id, 6)
        end
      end

    end

    context 'when business should not continue retrying' do
      before do
        business.update!(status: 'active') # Not in monitoring/active state
      end

      it 'stops retrying immediately' do
        expect(health_checker).not_to receive(:check_health)
        expect(render_service).not_to receive(:verify_domain)
        expect(described_class).not_to receive(:set)

        described_class.perform_now(business.id, 1)
      end

      it 'logs stop message' do
        expect(Rails.logger).to receive(:info).with(/Retry attempt/)
        expect(Rails.logger).to receive(:info)
          .with("[CertificatePropagationRetryJob] Stopping retries for business #{business.id}")

        described_class.perform_now(business.id, 1)
      end
    end

    context 'when business not found' do
      before do
        allow(Business).to receive(:find).with(999).and_raise(ActiveRecord::RecordNotFound, 'Not found')
      end

      it 'handles gracefully and logs error' do
        expect(Rails.logger).to receive(:error).with(/Business 999 not found/)
        expect { described_class.perform_now(999, 0) }.not_to raise_error
      end
    end

    context 'when job scheduling errors occur' do
      before do
        allow(health_checker).to receive(:check_health).and_return({ healthy: false, ssl_ready: false })
        allow(RenderDomainVerificationJob).to receive(:perform_later).and_raise(StandardError, 'Job Error')
      end

      it 'logs error but continues processing' do
        expect(Rails.logger).to receive(:error)
          .with('[CertificatePropagationRetryJob] Failed to schedule verification: Job Error')

        expect { described_class.perform_now(business.id, 1) }.not_to raise_error
      end
    end
  end

  describe 'private methods' do
    let(:job) { described_class.new }

    describe '#should_continue_retry?' do
      it 'returns true for valid monitoring business' do
        business.update!(status: 'cname_monitoring')
        expect(job.send(:should_continue_retry?, business, 2)).to be true
      end

      it 'returns true for active business' do
        business.update!(status: 'cname_active')
        expect(job.send(:should_continue_retry?, business, 2)).to be true
      end

      it 'returns false for non-eligible status' do
        business.update!(status: 'active')
        expect(job.send(:should_continue_retry?, business, 2)).to be false
      end

      it 'returns false when retry count exceeds max attempts' do
        expect(job.send(:should_continue_retry?, business, 6)).to be false
      end

      it 'returns true when retry count equals max attempts minus one' do
        expect(job.send(:should_continue_retry?, business, 5)).to be true
      end

      it 'returns false for non-custom domain' do
        business.update!(host_type: 'subdomain')
        expect(job.send(:should_continue_retry?, business, 2)).to be false
      end

      it 'returns false when hostname is blank' do
        business.hostname = ''
        expect(job.send(:should_continue_retry?, business, 2)).to be false
      end
    end

    describe '#ssl_now_working?' do
      before do
        allow(DomainHealthChecker).to receive(:new).with('example.com').and_return(health_checker)
      end

      it 'returns true when health check passes with SSL' do
        allow(health_checker).to receive(:check_health).and_return({ healthy: true, ssl_ready: true })
        expect(job.send(:ssl_now_working?, business)).to be true
      end

      it 'returns false when health check fails' do
        allow(health_checker).to receive(:check_health).and_return({ healthy: false, ssl_ready: false })
        expect(job.send(:ssl_now_working?, business)).to be false
      end

      it 'returns false when SSL not ready' do
        allow(health_checker).to receive(:check_health).and_return({ healthy: true, ssl_ready: false })
        expect(job.send(:ssl_now_working?, business)).to be false
      end

      it 'handles exceptions gracefully' do
        allow(health_checker).to receive(:check_health).and_raise(StandardError, 'Network error')
        expect(Rails.logger).to receive(:warn).with(/Health check failed for example.com/)
        expect(job.send(:ssl_now_working?, business)).to be false
      end
    end

    describe '#determine_domains_to_add' do
      it 'returns www domain for www canonical preference' do
        business.canonical_preference = 'www'
        result = job.send(:determine_domains_to_add, business)
        expect(result).to eq(['www.example.com'])
      end

      it 'returns apex domain for apex canonical preference' do
        business.update!(canonical_preference: 'apex')
        result = job.send(:determine_domains_to_add, business)
        expect(result).to eq(['example.com'])
      end

      it 'returns hostname as-is for nil preference' do
        business.canonical_preference = nil
        result = job.send(:determine_domains_to_add, business)
        expect(result).to eq(['example.com'])
      end
    end

    describe '#max_retry_attempts' do
      it 'returns 6 attempts' do
        expect(job.send(:max_retry_attempts)).to eq(6)
      end
    end

    describe '#calculate_next_delay' do
      it 'returns progressive delays' do
        expect(job.send(:calculate_next_delay, 0)).to eq(5)
        expect(job.send(:calculate_next_delay, 1)).to eq(10)
        expect(job.send(:calculate_next_delay, 2)).to eq(20)
        expect(job.send(:calculate_next_delay, 3)).to eq(30)
        expect(job.send(:calculate_next_delay, 4)).to eq(30)
        expect(job.send(:calculate_next_delay, 5)).to eq(30)
      end
    end
  end

  describe 'domain rebuild workflow integration' do
    let(:job) { described_class.new }

    before do
      allow(health_checker).to receive(:check_health).and_return({ healthy: false, ssl_ready: false })
      allow(render_service).to receive(:find_domain_by_name).with('example.com').and_return(apex_domain_data)
      allow(render_service).to receive(:find_domain_by_name).with('www.example.com').and_return(www_domain_data)
      allow(render_service).to receive(:remove_domain)
      allow(render_service).to receive(:add_domain)
      allow(render_service).to receive(:verify_domain)
    end

    it 'schedules domain rebuild continuation job after cleanup delay' do
      expect(DomainRebuildContinueJob).to receive_message_chain(:set, :perform_later)
        .with(wait: 10.seconds).with(business.id)

      job.send(:rebuild_domains_in_render, business)
    end

    it 'logs domain rebuild start and scheduling' do
      expect(Rails.logger).to receive(:info).with(/Starting domain rebuild/).ordered
      expect(Rails.logger).to receive(:info).with(/Removing existing domains/).ordered
      expect(Rails.logger).to receive(:info).with(/Removing domain: example.com/).ordered
      expect(Rails.logger).to receive(:info).with(/Removing domain: www.example.com/).ordered  
      expect(Rails.logger).to receive(:info).with(/Scheduling domain re-addition after 10 seconds/).ordered

      job.send(:rebuild_domains_in_render, business)
    end

    context 'when domain removal fails' do
      before do
        allow(render_service).to receive(:remove_domain).and_raise(RenderDomainService::RenderApiError, 'Remove failed')
      end

      it 'propagates the error' do
        expect { job.send(:rebuild_domains_in_render, business) }.to raise_error(RenderDomainService::RenderApiError)
      end

      it 'logs the error' do
        expect(Rails.logger).to receive(:error).with(/Failed to rebuild domains: Remove failed/)
        expect { job.send(:rebuild_domains_in_render, business) }.to raise_error(RenderDomainService::RenderApiError)
      end
    end
  end
end