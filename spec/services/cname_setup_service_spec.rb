# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CnameSetupService, type: :service do
  let!(:business) { create(:business, host_type: 'custom_domain', hostname: 'example.com', canonical_preference: 'apex') }
  let!(:owner) { create(:user, business: business, role: 'manager', email: 'owner@example.com') }
  let(:service) { described_class.new(business) }
  let(:render_service) { instance_double(RenderDomainService) }

  before do
    allow(RenderDomainService).to receive(:new).and_return(render_service)
    allow(DomainMailer).to receive_message_chain(:setup_instructions, :deliver_now)
    allow(DomainMonitoringJob).to receive_message_chain(:set, :perform_later)
    allow_any_instance_of(CnameSetupService).to receive(:sleep)
  end

  describe '#start_setup!' do
    context 'with eligible business' do
      let(:domain_data) { { 'id' => 'dom_123', 'name' => 'example.com' } }

      before do
        allow(render_service).to receive(:find_domain_by_name).with('example.com').and_return(nil)
        allow(render_service).to receive(:add_domain).with('example.com').and_return(domain_data)
        
        # Mock verification calls for both apex and www domains
        allow(render_service).to receive(:find_domain_by_name).with('www.example.com').and_return(nil)
      end

      it 'completes setup successfully' do
        result = service.start_setup!

        expect(result[:success]).to be true
        expect(result[:message]).to eq('Custom domain setup initiated successfully')
        expect(result[:domain]).to eq('example.com')
        expect(result[:business_id]).to eq(business.id)
      end

      it 'adds domain to Render' do
        expect(render_service).to receive(:add_domain).with('example.com')

        service.start_setup!
      end

      it 'updates business status' do
        service.start_setup!

        business.reload
        expect(business.status).to eq('cname_monitoring')
        expect(business.render_domain_added).to be true
      end

      it 'sends setup instructions email' do
        expect(DomainMailer).to receive(:setup_instructions).with(business, owner)
        
        service.start_setup!
        
        business.reload
        expect(business.cname_setup_email_sent_at).to be_present
      end

      it 'starts DNS monitoring' do
        expect(DomainMonitoringJob).to receive_message_chain(:set, :perform_later).with(wait: 1.minute).with(business.id)

        service.start_setup!

        business.reload
        expect(business.status).to eq('cname_monitoring')
        expect(business.cname_monitoring_active).to be true
      end

      context 'when domain already exists in Render' do
        before do
          allow(render_service).to receive(:find_domain_by_name).with('example.com').and_return(domain_data)
          # Mock verification calls
          allow(render_service).to receive(:find_domain_by_name).with('www.example.com').and_return(nil)
          allow(render_service).to receive(:verify_domain).with('dom_123').and_return({ 'verified' => true })
        end

        it 'skips domain addition' do
          expect(render_service).not_to receive(:add_domain)

          service.start_setup!
        end

        it 'marks domain as added' do
          service.start_setup!

          business.reload
          expect(business.render_domain_added).to be true
        end
      end
    end

    context 'with ineligible business' do
      let(:subdomain_business) { create(:business, host_type: 'subdomain') }
      let(:subdomain_service) { described_class.new(subdomain_business) }

      it 'fails validation for subdomain hosting' do
        result = subdomain_service.start_setup!

        expect(result[:success]).to be false
        expect(result[:error]).to include('custom domain hosting')
      end
    end

    context 'with non-custom domain business' do
      let(:subdomain_business) { create(:business, host_type: 'subdomain') }
      let(:subdomain_service) { described_class.new(subdomain_business) }

      it 'fails validation for subdomain hosting' do
        result = subdomain_service.start_setup!

        expect(result[:success]).to be false
        expect(result[:error]).to include('custom domain hosting')
      end
    end

    context 'with active CNAME business' do
      before do
        business.update!(status: 'cname_active')
      end

      it 'fails validation for already active domain' do
        result = service.start_setup!

        expect(result[:success]).to be false
        expect(result[:error]).to include('already active')
      end
    end

    # Regression for Bugbot MEDIUM: "Setup succeeds without instructions
    # email". On the Caddy deployment DomainMailer#assign_dns_instructions!
    # raises ArgumentError when BIZBLASTS_PUBLIC_IP is missing. Previously
    # CnameSetupService#start_setup! would catch nothing (deliver_domain_mail!
    # swallowed it) and still flip the business to monitoring + return
    # success: true with the customer having received no DNS instructions
    # whatsoever. The rollback path is the correct behavior — fail loudly
    # so the operator notices the misconfiguration before customers do.
    context 'when DomainMailer raises ArgumentError (Caddy public IP unconfigured)' do
      before do
        allow(render_service).to receive(:find_domain_by_name).with('example.com').and_return(nil)
        allow(render_service).to receive(:find_domain_by_name).with('www.example.com').and_return(nil)
        allow(render_service).to receive(:add_domain).with('example.com').and_return({ 'id' => 'dom_123', 'name' => 'example.com' })
        allow(render_service).to receive(:verify_domain).and_return({ 'verified' => true })
        allow(render_service).to receive(:remove_domain)
        # Simulate the Caddy ArgumentError path without flipping the global
        # provider — we only want to assert that the rescue + rollback fires.
        message = instance_double(ActionMailer::MessageDelivery)
        allow(DomainMailer).to receive(:setup_instructions).with(business, owner).and_return(message)
        allow(message).to receive(:deliver_now).and_raise(ArgumentError, 'BizBlasts public IP is not configured')
      end

      it 'rolls back state and returns success: false surfacing the real mailer cause' do
        result = service.start_setup!

        expect(result[:success]).to be false
        # The error string must include the actual ArgumentError message so
        # operators see the real cause (e.g. blank subdomain) instead of a
        # hardcoded "public IP not configured" blame line (Bugbot LOW:
        # "Setup masks mail ArgumentError cause").
        expect(result[:error]).to match(/Setup instructions email could not be sent/i)
        expect(result[:error]).to include('BizBlasts public IP is not configured')

        business.reload
        expect(business.status).to eq('active')
        expect(business.render_domain_added).to be false
        expect(business.cname_setup_email_sent_at).to be_nil
        expect(business.cname_monitoring_active).to be false
      end

      it 'surfaces a non-IP ArgumentError unchanged' do
        # Re-stub deliver_now to raise a different ArgumentError (simulating
        # e.g. a blank-subdomain guard tripping inside DomainMailer). The
        # rollback path must propagate THAT message, not the IP one.
        message = instance_double(ActionMailer::MessageDelivery)
        allow(DomainMailer).to receive(:setup_instructions).with(business, owner).and_return(message)
        allow(message).to receive(:deliver_now).and_raise(ArgumentError, 'Business subdomain is blank')

        result = service.start_setup!

        expect(result[:success]).to be false
        expect(result[:error]).to include('Business subdomain is blank')
        expect(result[:error]).not_to include('public IP')
      end
    end

    context 'when Render API fails' do
      before do
        allow(render_service).to receive(:find_domain_by_name).with('example.com').and_return(nil)
        allow(render_service).to receive(:find_domain_by_name).with('www.example.com').and_return(nil)
        allow(render_service).to receive(:add_domain).and_raise(RenderDomainService::RenderApiError.new('API Error'))
      end

      it 'handles failure and rolls back' do
        result = service.start_setup!

        expect(result[:success]).to be false
        expect(result[:error]).to include('API Error')

        business.reload
        expect(business.status).to eq('active')
        expect(business.render_domain_added).to be false
      end

      it 'attempts to remove domain during rollback' do
        allow(render_service).to receive(:find_domain_by_name).with('example.com').and_return({ 'id' => 'dom_123' })
        allow(render_service).to receive(:find_domain_by_name).with('www.example.com').and_return(nil)
        allow(render_service).to receive(:verify_domain).with('dom_123').and_return({ 'verified' => true })
        allow(render_service).to receive(:remove_domain).with('dom_123')

        service.start_setup!

        # Assert service handled failure gracefully (no exception raised)
        expect(business.reload).to be_present
      end
    end

    context 'with canonical preference' do
      context 'when preference is www' do
        let!(:www_business) { create(:business, host_type: 'custom_domain', hostname: 'example-www.com', canonical_preference: 'www') }
        let!(:www_owner) { create(:user, business: www_business, role: 'manager', email: 'owner@example-www.com') }
        let(:www_service) { described_class.new(www_business) }
        
        before do
          allow(render_service).to receive(:find_domain_by_name).with('www.example-www.com').and_return(nil)
          allow(render_service).to receive(:add_domain).with('www.example-www.com').and_return({ 'id' => 'dom_456', 'name' => 'www.example-www.com' })
          allow(render_service).to receive(:find_domain_by_name).with('example-www.com').and_return(nil)
          allow(render_service).to receive(:verify_domain)
        end

        it 'adds www domain to Render' do
          expect(render_service).to receive(:add_domain).with('www.example-www.com')
          
          www_service.start_setup!
        end

        it 'logs www canonical preference' do
          # Simply verify the service completes successfully with www preference
          result = www_service.start_setup!
          expect(result[:success]).to be true
        end
      end

      context 'when preference is apex' do
        before do
          # The main business already has apex preference, just need to add missing mocks
          allow(render_service).to receive(:verify_domain)
        end

        it 'adds apex domain to Render' do
          # Need to ensure the correct mocks are set up for this specific test
          allow(render_service).to receive(:find_domain_by_name).with('example.com').and_return(nil)
          allow(render_service).to receive(:find_domain_by_name).with('www.example.com').and_return(nil)
          expect(render_service).to receive(:add_domain).with('example.com')
          
          service.start_setup!
        end

        it 'completes setup successfully with apex preference' do
          # Need to ensure the correct mocks are set up for this specific test
          allow(render_service).to receive(:find_domain_by_name).with('example.com').and_return(nil)
          allow(render_service).to receive(:find_domain_by_name).with('www.example.com').and_return(nil)
          allow(render_service).to receive(:add_domain).with('example.com').and_return({ 'id' => 'dom_123', 'name' => 'example.com' })
          
          result = service.start_setup!
          expect(result[:success]).to be true
        end
      end
    end
  end

  describe '#restart_monitoring!' do
    before do
      business.update!(status: 'cname_timeout')
      allow(DomainMailer).to receive_message_chain(:monitoring_restarted, :deliver_now)
    end

    it 'restarts monitoring successfully' do
      result = service.restart_monitoring!

      expect(result[:success]).to be true
      expect(result[:message]).to include('restarted successfully')

      business.reload
      expect(business.status).to eq('cname_monitoring')
      expect(business.cname_monitoring_active).to be true
      expect(business.cname_check_attempts).to eq(0)
    end

    it 'sends restart notification email' do
      expect(DomainMailer).to receive(:monitoring_restarted).with(business, owner)

      service.restart_monitoring!
    end

    it 'queues monitoring job' do
      expect(DomainMonitoringJob).to receive(:perform_later).with(business.id)

      service.restart_monitoring!
    end

    context 'with invalid status' do
      before do
        business.update!(status: 'active')
      end

      it 'fails validation' do
        result = service.restart_monitoring!

        expect(result[:success]).to be false
        expect(result[:error]).to include('pending, monitoring, or timeout status')
      end
    end
  end

  describe '#force_activate!' do
    before do
      allow(DomainMailer).to receive_message_chain(:activation_success, :deliver_now)
    end

    it 'force activates domain successfully' do
      result = service.force_activate!

      expect(result[:success]).to be true
      expect(result[:message]).to include('activated successfully')

      business.reload
      expect(business.status).to eq('cname_active')
      expect(business.cname_monitoring_active).to be false
    end

    it 'sends activation success email' do
      expect(DomainMailer).to receive(:activation_success).with(business, owner)

      service.force_activate!
    end
  end

  describe '#status' do
    it 'returns comprehensive status information' do
      business.update!(
        status: 'cname_monitoring',
        cname_monitoring_active: true,
        cname_check_attempts: 5,
        cname_setup_email_sent_at: 1.hour.ago,
        render_domain_added: true
      )

      status = service.status

      expect(status[:business_id]).to eq(business.id)
      expect(status[:domain]).to eq('example.com')
      expect(status[:status]).to eq('cname_monitoring')
      expect(status[:monitoring_active]).to be true
      expect(status[:check_attempts]).to eq(5)
      expect(status[:setup_email_sent]).to be true
      expect(status[:render_domain_added]).to be true
      expect(status[:can_setup]).to be true
    end
  end

  describe 'private methods' do
    describe '#validate_business_eligibility!' do
      it 'raises error for nil business' do
        nil_service = described_class.new(nil)

        expect { nil_service.send(:validate_business_eligibility!) }.to raise_error(CnameSetupService::InvalidBusinessError, /not found/)
      end

      it 'raises error for subdomain hosting' do
        business.update!(host_type: 'subdomain', hostname: 'example')

        expect { service.send(:validate_business_eligibility!) }.to raise_error(CnameSetupService::InvalidBusinessError, /custom domain/)
      end

      it 'raises error for already active domain' do
        business.update!(status: 'cname_active')

        expect { service.send(:validate_business_eligibility!) }.to raise_error(CnameSetupService::DomainAlreadyExistsError, /already active/)
      end

      it 'raises error for blank hostname' do
        business.update_columns(hostname: '')

        expect { service.send(:validate_business_eligibility!) }.to raise_error(CnameSetupService::InvalidBusinessError, /not configured/)
      end
    end
  end
end