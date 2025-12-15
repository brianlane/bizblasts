# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DomainRebuildContinueJob, type: :job do
  include ActiveJob::TestHelper

  let!(:business) do
    create(:business,
      host_type: 'custom_domain',
      hostname: 'example.com',
      status: 'cname_active',
      canonical_preference: 'apex',
      render_domain_added: true
    )
  end

  let(:render_service) { instance_double(RenderDomainService) }

  before do
    allow(RenderDomainService).to receive(:new).and_return(render_service)
    allow(Business).to receive(:find).with(business.id).and_return(business)
    allow(RenderDomainVerificationJob).to receive(:perform_later)
    allow(RenderDomainVerificationJob).to receive_message_chain(:set, :perform_later)
    allow(render_service).to receive(:add_domain)
  end

  describe '#perform' do
    context 'with valid business' do
      it 're-adds domains based on canonical preference' do
        # For apex preference, should add only apex domain
        expect(render_service).to receive(:add_domain).with('example.com')

        described_class.perform_now(business.id)
      end

      it 'schedules verification jobs with staggered delays' do
        expect(RenderDomainVerificationJob).to receive(:perform_later).with('example.com')
        expect(RenderDomainVerificationJob).to receive_message_chain(:set, :perform_later)
          .with(wait: 30.seconds).with('www.example.com')

        described_class.perform_now(business.id)
      end

      it 'handles www canonical preference correctly' do
        business.canonical_preference = 'www'
        
        expect(render_service).to receive(:add_domain).with('www.example.com')

        described_class.perform_now(business.id)
      end

      it 'logs all steps of the process' do
        expect(Rails.logger).to receive(:info).with(/Continuing domain rebuild/).ordered
        expect(Rails.logger).to receive(:info).with(/Apex canonical: adding apex domain as primary/).ordered
        expect(Rails.logger).to receive(:info).with(/Re-adding domain: example.com/).ordered
        expect(Rails.logger).to receive(:info).with(/Scheduling verification after rebuild/).ordered
        expect(Rails.logger).to receive(:info).with(/Scheduling immediate verification for example.com/).ordered
        expect(Rails.logger).to receive(:info).with(/Scheduling verification for www.example.com in 30 seconds/).ordered
        expect(Rails.logger).to receive(:info).with(/Domain rebuild completed/).ordered

        described_class.perform_now(business.id)
      end
    end

    context 'when business not found' do
      before do
        allow(Business).to receive(:find).with(999).and_raise(ActiveRecord::RecordNotFound, 'Not found')
      end

      it 'handles gracefully and logs error' do
        expect(Rails.logger).to receive(:error).with(/Business 999 not found/)
        expect { described_class.perform_now(999) }.not_to raise_error
      end
    end

    context 'when business is not eligible' do
      before do
        business.update!(host_type: 'subdomain')
      end

      it 'stops processing and logs warning' do
        expect(Rails.logger).to receive(:warn).with(/Business .+ no longer eligible for domain rebuild/)
        expect(render_service).not_to receive(:add_domain)
        expect(RenderDomainVerificationJob).not_to receive(:perform_later)

        described_class.perform_now(business.id)
      end
    end

  end

  describe 'private methods' do
    let(:job) { described_class.new }

    describe '#determine_domains_to_add' do
      it 'returns www domain for www canonical preference' do
        business.canonical_preference = 'www'
        result = job.send(:determine_domains_to_add, business)
        expect(result).to eq(['www.example.com'])
      end

      it 'returns apex domain for apex canonical preference' do
        business.canonical_preference = 'apex'
        result = job.send(:determine_domains_to_add, business)
        expect(result).to eq(['example.com'])
      end

      it 'returns hostname as-is for nil preference' do
        business.canonical_preference = nil
        result = job.send(:determine_domains_to_add, business)
        expect(result).to eq(['example.com'])
      end
    end
  end

  describe 'canonical preference handling' do
    context 'with www preference' do
      before { business.canonical_preference = 'www' }

      it 'adds only www domain and schedules verification for both' do
        expect(render_service).to receive(:add_domain).with('www.example.com')
        expect(RenderDomainVerificationJob).to receive(:perform_later).with('example.com')
        expect(RenderDomainVerificationJob).to receive_message_chain(:set, :perform_later)
          .with(wait: 30.seconds).with('www.example.com')

        described_class.perform_now(business.id)
      end
    end

    context 'with apex preference' do
      before { business.canonical_preference = 'apex' }

      it 'adds only apex domain and schedules verification for both' do
        expect(render_service).to receive(:add_domain).with('example.com')
        expect(RenderDomainVerificationJob).to receive(:perform_later).with('example.com')
        expect(RenderDomainVerificationJob).to receive_message_chain(:set, :perform_later)
          .with(wait: 30.seconds).with('www.example.com')

        described_class.perform_now(business.id)
      end
    end
  end
end