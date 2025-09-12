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

  describe 'retry logic for rate limiting' do
    let(:initial_response) { instance_double(Net::HTTPResponse, code: '429', body: '{"error":"Rate limit exceeded"}') }
    let(:success_add_response) { instance_double(Net::HTTPResponse, code: '200', body: { id: 'dom-123', name: domain_name }.to_json) }
    let(:success_verify_response) { instance_double(Net::HTTPResponse, code: '200', body: { verified: true, domain_id: 'dom-123' }.to_json) }
    let(:success_list_response) { instance_double(Net::HTTPResponse, code: '200', body: [{ id: 'dom-123', name: domain_name, verified: true }].to_json) }

    before do
      # Mock the execute_request method to control responses
      allow(service).to receive(:sleep) # Don't actually sleep in tests
    end

    describe '#add_domain with rate limiting' do
      it 'retries on 429 and succeeds' do
        # First call returns 429, second call succeeds
        allow(service).to receive(:execute_request).and_return(initial_response, success_add_response)
        allow(service).to receive(:calculate_retry_delay).and_return(0.1)

        # Should not raise error and return parsed success response
        result = service.add_domain(domain_name)
        expect(result).to include('id' => 'dom-123', 'name' => domain_name)
        
        # Should have made 2 requests (initial + 1 retry)
        expect(service).to have_received(:execute_request).twice
      end

      it 'fails after max retries' do
        # All calls return 429
        allow(service).to receive(:execute_request).and_return(initial_response)
        allow(service).to receive(:calculate_retry_delay).and_return(0.1)

        expect { service.add_domain(domain_name) }.to raise_error(
          RenderDomainService::RateLimitError, 
          /Rate limit exceeded after 3 retries/
        )
        
        # Should have made 4 requests (initial + 3 retries)
        expect(service).to have_received(:execute_request).exactly(4).times
      end

      it 'respects Retry-After header when present' do
        response_with_retry_after = instance_double(Net::HTTPResponse, code: '429', body: '{}')
        allow(response_with_retry_after).to receive(:[]).with('Retry-After').and_return('5')
        allow(service).to receive(:execute_request).and_return(response_with_retry_after, success_add_response)

        service.add_domain(domain_name)
        
        # Should have calculated delay based on Retry-After header
        expect(service).to have_received(:sleep).with(5.0)
      end
    end

    describe '#calculate_retry_delay' do
      let(:response_without_retry_after) { instance_double(Net::HTTPResponse) }
      let(:response_with_retry_after) { instance_double(Net::HTTPResponse) }

      before do
        allow(response_without_retry_after).to receive(:[]).with('Retry-After').and_return(nil)
        allow(response_with_retry_after).to receive(:[]).with('Retry-After').and_return('10')
      end

      it 'uses Retry-After header when present' do
        delay = service.send(:calculate_retry_delay, 0, response_with_retry_after)
        expect(delay).to eq(10)
      end

      it 'uses exponential backoff when no Retry-After header' do
        # Mock rand to return consistent results for testing
        allow(service).to receive(:rand).and_return(0.5)
        
        # First retry: BASE_DELAY * (2^0) + jitter = 2 * 1 + (0.5 * 2 * 0.1) = 2.1
        delay = service.send(:calculate_retry_delay, 0, response_without_retry_after)
        expect(delay).to be_within(0.1).of(2.1)
        
        # Second retry: BASE_DELAY * (2^1) + jitter = 2 * 2 + (0.5 * 4 * 0.1) = 4.2
        delay = service.send(:calculate_retry_delay, 1, response_without_retry_after)
        expect(delay).to be_within(0.1).of(4.2)
      end

      it 'caps delay at MAX_DELAY' do
        delay = service.send(:calculate_retry_delay, 10, response_without_retry_after)
        expect(delay).to eq(60) # MAX_DELAY
      end

      it 'caps Retry-After header at MAX_DELAY' do
        large_retry_after = instance_double(Net::HTTPResponse)
        allow(large_retry_after).to receive(:[]).with('Retry-After').and_return('120')
        
        delay = service.send(:calculate_retry_delay, 0, large_retry_after)
        expect(delay).to eq(60) # MAX_DELAY
      end
    end

    describe 'integration with other methods' do
      it 'applies retry logic to verify_domain' do
        allow(service).to receive(:execute_request).and_return(initial_response, success_verify_response)
        allow(service).to receive(:calculate_retry_delay).and_return(0.1)

        result = service.verify_domain(domain_id)
        expect(result).to include('verified' => true, 'domain_id' => 'dom-123')
        expect(service).to have_received(:execute_request).twice
      end

      it 'applies retry logic to list_domains' do
        allow(service).to receive(:execute_request).and_return(initial_response, success_list_response)
        allow(service).to receive(:calculate_retry_delay).and_return(0.1)

        result = service.list_domains
        expect(result).to be_an(Array)
        expect(result.first).to include('id' => 'dom-123', 'name' => domain_name)
        expect(service).to have_received(:execute_request).twice
      end

      it 'applies retry logic to remove_domain' do
        success_delete = instance_double(Net::HTTPResponse, code: '204')
        allow(service).to receive(:execute_request).and_return(initial_response, success_delete)
        allow(service).to receive(:calculate_retry_delay).and_return(0.1)

        result = service.remove_domain(domain_id)
        expect(result).to be true
        expect(service).to have_received(:execute_request).twice
      end
    end
  end
end