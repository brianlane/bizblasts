# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DomainVerificationStrategy, type: :service do
  # This file asserts the :render variant of PROGRESS_COPY throughout ("waiting
  # for Render", "Render only", and so on), which it got for free while
  # DomainProvider defaulted to 'render'. The default is now 'caddy' (BizBlasts
  # is self-hosted), so pin the provider to keep these examples testing the copy
  # they were written against.
  #
  # KNOWN GAP: the :caddy branch of PROGRESS_COPY -- the one production actually
  # takes now -- has no equivalent coverage here. Worth adding.
  before { allow(DomainProvider).to receive(:provider_name).and_return('render') }

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

    # Regression: on Caddy a one-sided DNS pass (apex but not www, or vice
    # versa) must NOT activate the domain — the strategy needs to consume the
    # dual verification result rather than only the legacy single-host
    # CnameDnsChecker output (Bugbot HIGH: "Activation ignores dual DNS
    # checks"). On Render dual_result is informational and the legacy gate
    # still applies.
    context 'when caddy mode and dual_result is supplied' do
      let(:render_result) { { verified: true } }
      let(:health_result) { { healthy: true, ssl_ready: true } }
      let(:legacy_dns_pass) { { verified: true } }

      before do
        allow(DomainProvider).to receive(:caddy?).and_return(true)
      end

      it 'blocks success when only the apex side of the dual check verified' do
        dual_result = {
          overall_verified: false,
          apex_domain: { verified: true },
          www_domain: { verified: false }
        }

        result = strategy.determine_status(
          legacy_dns_pass, render_result, health_result, dual_result: dual_result
        )

        expect(result[:verified]).to be false
        expect(result[:dns_verified]).to be false
        expect(result[:should_continue]).to be true
      end

      it 'blocks success when only the www side of the dual check verified' do
        dual_result = {
          overall_verified: false,
          apex_domain: { verified: false },
          www_domain: { verified: true }
        }

        result = strategy.determine_status(
          legacy_dns_pass, render_result, health_result, dual_result: dual_result
        )

        expect(result[:verified]).to be false
        expect(result[:dns_verified]).to be false
      end

      it 'allows success when both apex and www verified in dual check' do
        dual_result = {
          overall_verified: true,
          apex_domain: { verified: true },
          www_domain: { verified: true }
        }

        result = strategy.determine_status(
          legacy_dns_pass, render_result, health_result, dual_result: dual_result
        )

        expect(result[:verified]).to be true
        expect(result[:dns_verified]).to be true
        expect(result[:should_continue]).to be false
      end
    end

    context 'when render mode (default) ignores dual_result for the legacy gate' do
      let(:render_result) { { verified: true } }
      let(:health_result) { { healthy: true, ssl_ready: true } }

      it 'still trusts legacy single-host dns_result on Render even if dual_result disagrees' do
        # Render mode: single-host CNAME pass remains authoritative so existing
        # call sites (controller actions written for Render's CNAME flow)
        # don't regress when dual_result eventually plumbs in everywhere.
        allow(DomainProvider).to receive(:caddy?).and_return(false)

        dual_result = {
          overall_verified: false,
          apex_domain: { verified: false },
          www_domain: { verified: true }
        }

        result = strategy.determine_status(
          { verified: true }, render_result, health_result, dual_result: dual_result
        )

        expect(result[:verified]).to be true
        expect(result[:dns_verified]).to be true
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
  # Same reason as the DomainVerificationStrategy block above: #status_reason
  # reads the :render variant of PROGRESS_COPY, and DomainProvider now defaults
  # to 'caddy'. Same KNOWN GAP -- no caddy-copy coverage.
  before { allow(DomainProvider).to receive(:provider_name).and_return('render') }

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

      # Regression for Bugbot MEDIUM: "Caddy status still says CNAME". On the
      # Caddy deployment the status panel should reference apex + www A
      # records and "BizBlasts verification" rather than "CNAME record" /
      # "Render verification".
      context 'in caddy mode' do
        before do
          allow(DomainProvider).to receive(:caddy?).and_return(true)
        end

        it 'uses Caddy-aware copy for the all-pending state' do
          policy = described_class.new(false, false, false)
          expect(policy.status_reason).to eq(
            'Waiting for apex + www A records, BizBlasts verification, and health check'
          )
          expect(policy.status_reason).not_to include('CNAME')
          expect(policy.status_reason).not_to include('Render')
        end

        it 'uses Caddy-aware copy for the DNS-only state' do
          policy = described_class.new(true, false, false)
          expect(policy.status_reason).to eq(
            'DNS configured, waiting for BizBlasts verification and health check'
          )
        end

        it 'uses Caddy-aware copy for the DNS+provider state' do
          policy = described_class.new(true, true, false)
          expect(policy.status_reason).to eq(
            'DNS and BizBlasts verified, waiting for domain to return HTTP 200'
          )
        end
      end
    end
  end
end

# -----------------------------------------------------------------------------
# Caddy-mode behaviour
#
# The blocks above pin the provider to 'render'. This covers the caddy branch --
# the one the self-hosted deployment actually takes. Previously untested.
# -----------------------------------------------------------------------------
RSpec.describe 'DomainVerificationStrategy in caddy mode', type: :service do
  before { allow(DomainProvider).to receive(:provider_name).and_return('caddy') }

  describe 'InProgressVerificationPolicy#status_reason' do
    it 'describes the apex + www A records rather than a CNAME' do
      policy = InProgressVerificationPolicy.new(false, false, false)

      expect(policy.status_reason)
        .to eq('Waiting for apex + www A records, BizBlasts verification, and health check')
    end

    it 'attributes verification to BizBlasts, not Render' do
      policy = InProgressVerificationPolicy.new(false, true, false)

      expect(policy.status_reason).to eq('BizBlasts verified, waiting for DNS and health check')
    end

    # These strings are surfaced to business owners in the domain status UI.
    # Naming a hosting provider we no longer use would be actively misleading.
    # Also asserts each state produces copy at all: the caddy table is a
    # separate hash from the render one, and a key present in render but missing
    # from caddy would silently yield nil here rather than fail loudly.
    it 'produces caddy copy for every reachable state, never mentioning Render' do
      [true, false].repeated_permutation(4) do |dns, render, health, ssl|
        state = "[dns=#{dns}, render=#{render}, health=#{health}, ssl=#{ssl}]"
        reason = InProgressVerificationPolicy.new(dns, render, health, ssl).status_reason

        expect(reason).to be_present, "no status_reason for #{state}"
        expect(reason).not_to match(/render/i),
          "expected no 'Render' for #{state}, got: #{reason.inspect}"
      end
    end
  end

  describe '.dns_verified_for' do
    # On Caddy both apex and www must resolve, so the dual-check result is
    # authoritative. Deriving the UI's "DNS verified" row from dns_result alone
    # would flash green on one host while activation correctly stayed blocked.
    it 'defers to the dual check when it reports overall_verified' do
      expect(
        DomainVerificationStrategy.dns_verified_for({ verified: true }, { overall_verified: false })
      ).to be false
    end

    it 'accepts when the dual check reports overall success' do
      expect(
        DomainVerificationStrategy.dns_verified_for({ verified: false }, { overall_verified: true })
      ).to be true
    end

    it 'falls back to the single result when no dual check was performed' do
      expect(DomainVerificationStrategy.dns_verified_for({ verified: true }, nil)).to be true
      expect(DomainVerificationStrategy.dns_verified_for({ verified: false }, nil)).to be false
    end
  end
end
