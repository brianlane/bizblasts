# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DomainMonitoringService, type: :service do
  let!(:business) do
    create(:business,
      tier: 'premium',
      host_type: 'custom_domain',
      hostname: 'example.com',
      status: 'cname_monitoring',
      cname_monitoring_active: true,
      cname_check_attempts: 2
    )
  end

  let(:service) { described_class.new(business) }
  let(:dns_checker) { instance_double(CnameDnsChecker) }
  let(:render_service) { instance_double(RenderDomainService) }
  let(:health_checker) { instance_double(DomainHealthChecker) }
  let(:verification_strategy) { instance_double(DomainVerificationStrategy) }

  before do
    allow(CnameDnsChecker).to receive(:new).and_return(dns_checker)
    allow(RenderDomainService).to receive(:new).and_return(render_service)
    allow(DomainHealthChecker).to receive(:new).and_return(health_checker)
    allow(DomainVerificationStrategy).to receive(:new).and_return(verification_strategy)
  end

  describe '#perform_check!' do
    let(:dns_result) { { verified: true, target: 'bizblasts.onrender.com' } }
    let(:render_result) { { verified: true } }
    let(:health_result) { { healthy: true, status_code: 200 } }
    let(:verification_result) do
      {
        verified: true,
        should_continue: false,
        dns_verified: true,
        render_verified: true,
        health_verified: true,
        status_reason: 'Domain fully verified and responding with HTTP 200'
      }
    end

    before do
      allow(dns_checker).to receive(:verify_cname).and_return(dns_result)
      allow(render_service).to receive(:find_domain_by_name).and_return({ 'id' => 'dom_123' })
      allow(render_service).to receive(:verify_domain).and_return({ 'verified' => true })
      allow(health_checker).to receive(:check_health).and_return(health_result)
      allow(verification_strategy).to receive(:determine_status).and_return(verification_result)
      
      # Mock business state updates
      allow(business).to receive(:increment_cname_check!)
      allow(business).to receive(:mark_domain_health_verified!)
      allow(business).to receive(:cname_success!)
      allow(business).to receive(:cname_timeout!)
      allow(business).to receive(:mark_domain_health_unverified!)
    end

    context 'when all checks pass (happy path)' do
      it 'returns success result with verification details' do
        allow(DomainMailer).to receive_message_chain(:activation_success, :deliver_now)
        allow(business.users).to receive_message_chain(:where, :first).and_return(create(:user))

        result = service.perform_check!

        expect(result[:success]).to be true
        expect(result[:verified]).to be true
        expect(result[:should_continue]).to be false
        expect(result[:dns_result]).to eq(dns_result)
        expect(result[:render_result]).to eq(render_result)
        expect(result[:health_result]).to eq(health_result)
      end

      it 'updates business state correctly' do
        allow(DomainMailer).to receive_message_chain(:activation_success, :deliver_now)
        allow(business.users).to receive_message_chain(:where, :first).and_return(create(:user))

        service.perform_check!

        expect(business).to have_received(:increment_cname_check!)
        expect(business).to have_received(:mark_domain_health_verified!)
        expect(business).to have_received(:cname_success!)
      end

      it 'sends activation success email' do
        owner = create(:user, business: business, role: 'manager')
        allow(business.users).to receive_message_chain(:where, :first).and_return(owner)
        
        mailer = instance_double(ActionMailer::MessageDelivery)
        expect(DomainMailer).to receive(:activation_success).with(business, owner).and_return(mailer)
        expect(mailer).to receive(:deliver_now)

        service.perform_check!
      end
    end

    context 'when verification fails but should continue' do
      let(:verification_result) do
        {
          verified: false,
          should_continue: true,
          dns_verified: true,
          render_verified: false,
          health_verified: false,
          status_reason: 'DNS configured, waiting for Render verification and health check'
        }
      end

      it 'returns continue result' do
        result = service.perform_check!

        expect(result[:success]).to be true
        expect(result[:verified]).to be false
        expect(result[:should_continue]).to be true
        expect(result[:next_check_in]).to eq('5 minutes')
      end

      it 'updates health status appropriately' do
        service.perform_check!

        expect(business).to have_received(:increment_cname_check!)
        expect(business).to have_received(:mark_domain_health_unverified!)
        expect(business).not_to have_received(:cname_success!)
      end
    end

    context 'when maximum attempts reached (timeout)' do
      let(:verification_result) do
        {
          verified: false,
          should_continue: false,
          dns_verified: false,
          render_verified: false,
          health_verified: false,
          status_reason: 'Maximum verification attempts reached'
        }
      end

      it 'returns timeout result' do
        allow(DomainMailer).to receive_message_chain(:timeout_help, :deliver_now)
        allow(business.users).to receive_message_chain(:where, :first).and_return(create(:user))

        result = service.perform_check!

        expect(result[:success]).to be true
        expect(result[:verified]).to be false
        expect(result[:should_continue]).to be false
        expect(result[:next_check_in]).to eq('stopped')
      end

      it 'updates business to timeout state' do
        allow(DomainMailer).to receive_message_chain(:timeout_help, :deliver_now)
        allow(business.users).to receive_message_chain(:where, :first).and_return(create(:user))

        service.perform_check!

        expect(business).to have_received(:cname_timeout!)
      end

      it 'sends timeout help email' do
        owner = create(:user, business: business, role: 'manager')
        allow(business.users).to receive_message_chain(:where, :first).and_return(owner)
        
        mailer = instance_double(ActionMailer::MessageDelivery)
        expect(DomainMailer).to receive(:timeout_help).with(business, owner).and_return(mailer)
        expect(mailer).to receive(:deliver_now)

        service.perform_check!
      end
    end

    context 'when health check passes but DNS/Render fail' do
      let(:verification_result) do
        {
          verified: false,
          should_continue: true,
          dns_verified: false,
          render_verified: false,
          health_verified: true,
          status_reason: 'Health verified, waiting for DNS and Render verification'
        }
      end

      it 'still marks health as verified' do
        service.perform_check!

        expect(business).to have_received(:mark_domain_health_verified!)
        expect(business).not_to have_received(:cname_success!)
      end
    end

    context 'when business is not eligible for monitoring' do
      before do
        allow(service).to receive(:validate_monitoring_state!).and_raise(described_class::MonitoringError.new('Not eligible'))
      end

      it 'raises monitoring error' do
        expect { service.perform_check! }.to raise_error(described_class::MonitoringError, 'Not eligible')
      end
    end

    context 'when DNS check fails' do
      before do
        allow(dns_checker).to receive(:verify_cname).and_raise(StandardError.new('DNS lookup failed'))
      end

      it 'propagates the error' do
        expect { service.perform_check! }.to raise_error(StandardError, 'DNS lookup failed')
      end
    end

    context 'when render check fails' do
      before do
        allow(render_service).to receive(:find_domain_by_name).and_raise(StandardError.new('Render API error'))
      end

      it 'propagates the error' do
        expect { service.perform_check! }.to raise_error(StandardError, 'Render API error')
      end
    end

    context 'when health check fails' do
      before do
        allow(health_checker).to receive(:check_health).and_raise(StandardError.new('Health check failed'))
      end

      it 'propagates the error' do
        expect { service.perform_check! }.to raise_error(StandardError, 'Health check failed')
      end
    end
  end

  describe '#validate_monitoring_state!' do
    context 'with valid business state' do
      it 'does not raise error' do
        expect { service.send(:validate_monitoring_state!) }.not_to raise_error
      end
    end

    context 'when business is not premium tier' do
      before { business.update!(tier: 'free') }

      it 'raises monitoring error' do
        expect { service.send(:validate_monitoring_state!) }.to raise_error(described_class::MonitoringError)
      end
    end

    context 'when business is not custom domain type' do
      before { business.update!(host_type: 'subdomain') }

      it 'raises monitoring error' do
        expect { service.send(:validate_monitoring_state!) }.to raise_error(described_class::MonitoringError)
      end
    end

    context 'when hostname is blank' do
      before { business.update!(hostname: '') }

      it 'raises monitoring error' do
        expect { service.send(:validate_monitoring_state!) }.to raise_error(described_class::MonitoringError)
      end
    end

    context 'when monitoring is not active' do
      before { business.update!(cname_monitoring_active: false) }

      it 'raises monitoring error' do
        expect { service.send(:validate_monitoring_state!) }.to raise_error(described_class::MonitoringError)
      end
    end
  end

  describe '#check_render_verification' do
    context 'when domain exists and is verified' do
      before do
        allow(render_service).to receive(:find_domain_by_name).with('example.com').and_return({ 'id' => 'dom_123' })
        allow(render_service).to receive(:verify_domain).with('dom_123').and_return({ 'verified' => true })
      end

      it 'returns verified result' do
        result = service.send(:check_render_verification)
        expect(result[:verified]).to be true
      end
    end

    context 'when domain does not exist in Render' do
      before do
        allow(render_service).to receive(:find_domain_by_name).with('example.com').and_return(nil)
      end

      it 'returns unverified result' do
        result = service.send(:check_render_verification)
        expect(result[:verified]).to be false
        expect(result[:error]).to include('not found')
      end
    end

    context 'when Render API fails' do
      before do
        allow(render_service).to receive(:find_domain_by_name).and_raise(StandardError.new('API error'))
      end

      it 'returns error result' do
        result = service.send(:check_render_verification)
        expect(result[:verified]).to be false
        expect(result[:error]).to include('API error')
      end
    end
  end

  describe '#check_domain_health' do
    let(:health_result) { { healthy: true, status_code: 200 } }

    before do
      allow(health_checker).to receive(:check_health).and_return(health_result)
    end

    it 'delegates to health checker' do
      result = service.send(:check_domain_health)
      expect(result).to eq(health_result)
      expect(health_checker).to have_received(:check_health)
    end

    context 'when health checker raises exception' do
      before do
        allow(health_checker).to receive(:check_health).and_raise(StandardError.new('Connection failed'))
      end

      it 'returns unhealthy result with error' do
        result = service.send(:check_domain_health)
        
        expect(result[:healthy]).to be false
        expect(result[:error]).to include('Connection failed')
        expect(result[:checked_at]).to be_within(1.second).of(Time.current)
      end
    end
  end
end
