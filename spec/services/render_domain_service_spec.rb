# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RenderDomainService, type: :service do
  let(:service) { described_class.new }
  let(:domain_name) { 'example.com' }
  let(:domain_id) { 'dom_123456' }

  before do
    ENV['RENDER_API_KEY'] = 'test_api_key'
    ENV['RENDER_SERVICE_ID'] = 'srv_123456'
  end

  after do
    ENV.delete('RENDER_API_KEY')
    ENV.delete('RENDER_SERVICE_ID')
  end

  describe '#initialize' do
    context 'with valid credentials' do
      it 'initializes successfully' do
        expect { service }.not_to raise_error
      end
    end

    context 'without API key' do
      before { ENV.delete('RENDER_API_KEY') }

      it 'raises InvalidCredentialsError' do
        expect { service }.to raise_error(RenderDomainService::InvalidCredentialsError, /RENDER_API_KEY/)
      end
    end

    context 'without service ID' do
      before { ENV.delete('RENDER_SERVICE_ID') }

      it 'raises InvalidCredentialsError' do
        expect { service }.to raise_error(RenderDomainService::InvalidCredentialsError, /RENDER_SERVICE_ID/)
      end
    end
  end

  describe '#add_domain' do
    let(:response_body) { { id: domain_id, name: domain_name, verified: false }.to_json }
    let(:successful_response) { instance_double(Net::HTTPResponse, code: '200', body: response_body) }

    before do
      allow(service).to receive(:make_request).and_return(successful_response)
    end

    it 'adds domain successfully' do
      result = service.add_domain(domain_name)

      expect(result['id']).to eq(domain_id)
      expect(result['name']).to eq(domain_name)
    end

    it 'calls the correct API endpoint' do
      expect(service).to receive(:make_request).with(
        URI('https://api.render.com/v1/services/srv_123456/custom-domains'),
        :post,
        { name: domain_name }
      )

      service.add_domain(domain_name)
    end

    context 'when API returns error' do
      let(:error_response) { instance_double(Net::HTTPResponse, code: '400', body: '{"error": "Domain already exists"}') }

      before do
        allow(service).to receive(:make_request).and_return(error_response)
      end

      it 'raises RenderApiError' do
        expect { service.add_domain(domain_name) }.to raise_error(RenderDomainService::RenderApiError, /Domain already exists/)
      end
    end
  end

  describe '#verify_domain' do
    let(:response_body) { { verified: true, domain_id: domain_id }.to_json }
    let(:successful_response) { instance_double(Net::HTTPResponse, code: '200', body: response_body) }

    before do
      allow(service).to receive(:make_request).and_return(successful_response)
    end

    it 'verifies domain successfully' do
      result = service.verify_domain(domain_id)

      expect(result['verified']).to be true
      expect(result['domain_id']).to eq(domain_id)
    end

    it 'calls the correct API endpoint' do
      expect(service).to receive(:make_request).with(
        URI("https://api.render.com/v1/services/srv_123456/custom-domains/#{domain_id}/verify"),
        :post,
        {}
      )

      service.verify_domain(domain_id)
    end
  end

  describe '#list_domains' do
    let(:domains) { [{ id: domain_id, name: domain_name, verified: true }] }
    let(:response_body) { domains.to_json }
    let(:successful_response) { instance_double(Net::HTTPResponse, code: '200', body: response_body) }

    before do
      allow(service).to receive(:make_request).and_return(successful_response)
    end

    it 'lists domains successfully' do
      result = service.list_domains
      expect(result.map(&:deep_symbolize_keys)).to eq(domains)
      expect(result.first['name']).to eq(domain_name)
    end
  end

  describe '#remove_domain' do
    let(:successful_response) { instance_double(Net::HTTPResponse, code: '204') }

    before do
      allow(service).to receive(:make_request).and_return(successful_response)
    end

    it 'removes domain successfully' do
      result = service.remove_domain(domain_id)

      expect(result).to be true
    end

    it 'calls the correct API endpoint' do
      expect(service).to receive(:make_request).with(
        URI("https://api.render.com/v1/services/srv_123456/custom-domains/#{domain_id}"),
        :delete
      )

      service.remove_domain(domain_id)
    end
  end

  describe '#find_domain_by_name' do
    let(:domains) { [{ 'id' => domain_id, 'name' => domain_name, 'verified' => true }] }

    before do
      allow(service).to receive(:list_domains).and_return(domains)
    end

    it 'finds domain by name' do
      result = service.find_domain_by_name(domain_name)

      expect(result['name']).to eq(domain_name)
      expect(result['id']).to eq(domain_id)
    end

    it 'returns nil for non-existent domain' do
      result = service.find_domain_by_name('nonexistent.com')

      expect(result).to be_nil
    end
  end

  describe '#domain_status' do
    context 'when domain exists and is verified' do
      let(:domains) { [{ 'id' => domain_id, 'name' => domain_name, 'verified' => true }] }

      before do
        allow(service).to receive(:list_domains).and_return(domains)
      end

      it 'returns correct status' do
        result = service.domain_status(domain_name)
        expect(result[:exists]).to be true
        expect(result[:verified]).to be true
        expect(result[:domain_id]).to eq(domain_id)
      end
    end

    context 'when domain does not exist' do
      before do
        allow(service).to receive(:list_domains).and_return([])
      end

      it 'returns correct status' do
        result = service.domain_status(domain_name)

        expect(result[:exists]).to be false
        expect(result[:verified]).to be false
        expect(result[:domain_id]).to be_nil
      end
    end
  end
end