# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DomainVerificationStrategy, type: :service do
  let(:business) { create(:business, cname_check_attempts: 5) }
  let(:strategy) { described_class.new(business) }

  let(:dns_result) { { verified: false } }
  let(:render_result) { { verified: false } }
  let(:health_result) { { healthy: false } }

  describe '#determine_status' do
    context 'when all checks pass (success case)' do
      let(:dns_result) { { verified: true } }
      let(:render_result) { { verified: true } }
      let(:health_result) { { healthy: true, ssl_ready: true } }

      it 'returns success status' do
        result = strategy.determine_status(dns_result, render_result, health_result)

        expect(result[:verified]).to be true
        expect(result[:should_continue]).to be false
        expect(result[:dns_verified]).to be true
        expect(result[:render_verified]).to be true
        expect(result[:health_verified]).to be true
        expect(result[:status_reason]).to eq('Domain fully verified and responding with HTTPS (SSL ready)')
      end
    end

    context 'when maximum attempts reached (timeout case)' do
      let(:business) { create(:business, cname_check_attempts: 11) } # Next increment will be 12

      it 'returns timeout status regardless of check results' do
        result = strategy.determine_status(dns_result, render_result, health_result)

        expect(result[:verified]).to be false
        expect(result[:should_continue]).to be false
        expect(result[:status_reason]).to eq('Maximum verification attempts reached')
      end
    end

    context 'when in progress (various combinations)' do
      context 'with no checks passed' do
        it 'returns appropriate in-progress status' do
          result = strategy.determine_status(dns_result, render_result, health_result)

          expect(result[:verified]).to be false
          expect(result[:should_continue]).to be true
          expect(result[:status_reason]).to eq('Waiting for CNAME record, Render verification, and health check')
        end
      end

      context 'with only DNS passed' do
        let(:dns_result) { { verified: true } }

        it 'returns DNS-only status' do
          result = strategy.determine_status(dns_result, render_result, health_result)

          expect(result[:verified]).to be false
          expect(result[:should_continue]).to be true
          expect(result[:status_reason]).to eq('DNS configured, waiting for Render verification and health check')
        end
      end

      context 'with only Render passed' do
        let(:render_result) { { verified: true } }

        it 'returns Render-only status' do
          result = strategy.determine_status(dns_result, render_result, health_result)

          expect(result[:verified]).to be false
          expect(result[:should_continue]).to be true
          expect(result[:status_reason]).to eq('Render verified, waiting for DNS and health check')
        end
      end

      context 'with only health check passed' do
        let(:health_result) { { healthy: true } }

        it 'returns health-only status' do
          result = strategy.determine_status(dns_result, render_result, health_result)

          expect(result[:verified]).to be false
          expect(result[:should_continue]).to be true
          expect(result[:status_reason]).to eq('Health verified, waiting for DNS and Render verification')
        end
      end

      context 'with DNS and Render passed' do
        let(:dns_result) { { verified: true } }
        let(:render_result) { { verified: true } }

        it 'returns DNS+Render status' do
          result = strategy.determine_status(dns_result, render_result, health_result)

          expect(result[:verified]).to be false
          expect(result[:should_continue]).to be true
          expect(result[:status_reason]).to eq('DNS and Render verified, waiting for domain to return HTTP 200')
        end
      end

      context 'with DNS and health passed' do
        let(:dns_result) { { verified: true } }
        let(:health_result) { { healthy: true } }

        it 'returns DNS+health status' do
          result = strategy.determine_status(dns_result, render_result, health_result)

          expect(result[:verified]).to be false
          expect(result[:should_continue]).to be true
          expect(result[:status_reason]).to eq('DNS and health verified, waiting for Render verification')
        end
      end

      context 'with Render and health passed' do
        let(:render_result) { { verified: true } }
        let(:health_result) { { healthy: true } }

        it 'returns Render+health status' do
          result = strategy.determine_status(dns_result, render_result, health_result)

          expect(result[:verified]).to be false
          expect(result[:should_continue]).to be true
          expect(result[:status_reason]).to eq('Render and health verified, waiting for DNS propagation')
        end
      end
    end
  end
end

RSpec.describe SuccessVerificationPolicy, type: :service do
  let(:policy) { described_class.new }

  describe '#verified?' do
    it 'returns true' do
      expect(policy.verified?).to be true
    end
  end

  describe '#should_continue?' do
    it 'returns false' do
      expect(policy.should_continue?).to be false
    end
  end

  describe '#status_reason' do
    it 'returns success message' do
      expect(policy.status_reason).to eq('Domain fully verified and responding with HTTPS (SSL ready)')
    end
  end
end

RSpec.describe TimeoutVerificationPolicy, type: :service do
  let(:policy) { described_class.new }

  describe '#verified?' do
    it 'returns false' do
      expect(policy.verified?).to be false
    end
  end

  describe '#should_continue?' do
    it 'returns false' do
      expect(policy.should_continue?).to be false
    end
  end

  describe '#status_reason' do
    it 'returns timeout message' do
      expect(policy.status_reason).to eq('Maximum verification attempts reached')
    end
  end
end

RSpec.describe InProgressVerificationPolicy, type: :service do
  describe '#verified?' do
    it 'always returns false' do
      policy = described_class.new(true, true, false)
      expect(policy.verified?).to be false
    end
  end

  describe '#should_continue?' do
    it 'always returns true' do
      policy = described_class.new(false, false, false)
      expect(policy.should_continue?).to be true
    end
  end

  describe '#status_reason' do
    context 'with different verification states' do
      it 'returns appropriate message for all pending' do
        policy = described_class.new(false, false, false)
        expect(policy.status_reason).to eq('Waiting for CNAME record, Render verification, and health check')
      end

      it 'returns appropriate message for DNS only' do
        policy = described_class.new(true, false, false)
        expect(policy.status_reason).to eq('DNS configured, waiting for Render verification and health check')
      end

      it 'returns appropriate message for Render only' do
        policy = described_class.new(false, true, false)
        expect(policy.status_reason).to eq('Render verified, waiting for DNS and health check')
      end

      it 'returns appropriate message for health only' do
        policy = described_class.new(false, false, true)
        expect(policy.status_reason).to eq('Health verified, waiting for DNS and Render verification')
      end

      it 'returns appropriate message for DNS and Render' do
        policy = described_class.new(true, true, false)
        expect(policy.status_reason).to eq('DNS and Render verified, waiting for domain to return HTTP 200')
      end

      it 'returns appropriate message for DNS and health' do
        policy = described_class.new(true, false, true)
        expect(policy.status_reason).to eq('DNS and health verified, waiting for Render verification')
      end

      it 'returns appropriate message for Render and health' do
        policy = described_class.new(false, true, true)
        expect(policy.status_reason).to eq('Render and health verified, waiting for DNS propagation')
      end

      it 'returns generic message for unknown state' do
        # This shouldn't happen in practice, but test the fallback
        policy = described_class.new(true, true, true) # This would be success, not in-progress
        allow(policy).to receive(:verification_state).and_return(:unknown)
        expect(policy.status_reason).to eq('Domain configuration is in progress')
      end
    end
  end
end
