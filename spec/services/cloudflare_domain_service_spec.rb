# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CloudflareDomainService, type: :service do
  let(:token) { 'cf-token-secret-value' }
  let(:zone_id) { 'zone123' }
  let(:service) { described_class.new }
  let(:http) { instance_double(Net::HTTP) }

  around do |example|
    originals = {
      'CLOUDFLARE_ZONE_ID' => ENV['CLOUDFLARE_ZONE_ID'],
      'CLOUDFLARE_SAAS_API_TOKEN' => ENV['CLOUDFLARE_SAAS_API_TOKEN'],
      'BIZBLASTS_DOMAIN_PROVIDER' => ENV['BIZBLASTS_DOMAIN_PROVIDER']
    }
    ENV['CLOUDFLARE_ZONE_ID'] = zone_id
    ENV['CLOUDFLARE_SAAS_API_TOKEN'] = token
    ENV['BIZBLASTS_DOMAIN_PROVIDER'] = 'cloudflare'
    example.run
  ensure
    originals.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  before do
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)
  end

  def json_response(code, body)
    instance_double(Net::HTTPResponse, code: code.to_s, body: body.is_a?(String) ? body : JSON.generate(body))
  end

  def hostname_payload(hostname, id:, status: 'pending', ssl_status: 'pending_validation', extra: {})
    {
      'id' => id,
      'hostname' => hostname,
      'status' => status,
      'ownership_verification' => extra[:ownership_verification],
      'ssl' => {
        'status' => ssl_status,
        'method' => 'http',
        'type' => 'dv',
        'validation_records' => extra[:validation_records]
      }.compact
    }.compact
  end

  def hostname_from(request)
    query = request.path.to_s.split('?', 2)[1]
    return if query.blank?

    URI.decode_www_form(query).to_h['hostname']
  end

  describe '.new' do
    it 'raises when the zone id is missing and does not mention the token' do
      ENV['CLOUDFLARE_ZONE_ID'] = ''
      expect { described_class.new }.to raise_error(described_class::InvalidCredentialsError, /CLOUDFLARE_ZONE_ID/)
    end

    it 'raises when the token is missing without echoing a previous token' do
      ENV['CLOUDFLARE_SAAS_API_TOKEN'] = '   '
      expect { described_class.new }.to raise_error(described_class::InvalidCredentialsError, /CLOUDFLARE_SAAS_API_TOKEN/) do |error|
        expect(error.message).not_to include(token)
      end
    end
  end

  describe 'provider selection' do
    it 'is the provider when BIZBLASTS_DOMAIN_PROVIDER=cloudflare' do
      expect(DomainProvider.cloudflare?).to be true
      expect(DomainProvider.caddy?).to be false
      expect(DomainProvider.current).to be_a(described_class)
    end
  end

  describe '#add_domain' do
    it 'returns the existing hostname without creating a duplicate' do
      existing = hostname_payload('example.com', id: 'host-1')
      requests = []
      allow(http).to receive(:request) do |request|
        requests << request
        json_response(200, { 'success' => true, 'result' => [existing] })
      end

      result = service.add_domain('Example.com')

      expect(result['id']).to eq('host-1')
      expect(result['name']).to eq('example.com')
      expect(result['verified']).to be false
      expect(requests.length).to eq(1)
      expect(requests.first).to be_a(Net::HTTP::Get)
      expect(requests.first.path).to include('hostname=example.com')
      expect(requests.first['Authorization']).to eq("Bearer #{token}")
    end

    it 'creates a hostname with http dv ssl when lookup misses' do
      created = hostname_payload('example.com', id: 'host-new', status: 'pending', ssl_status: 'initializing')
      requests = []
      allow(http).to receive(:request) do |request|
        requests << request
        if request.is_a?(Net::HTTP::Get)
          json_response(200, { 'success' => true, 'result' => [] })
        else
          json_response(201, { 'success' => true, 'result' => created })
        end
      end

      result = service.add_domain('example.com')

      expect(result['id']).to eq('host-new')
      post = requests.find { |request| request.is_a?(Net::HTTP::Post) }
      expect(post.path).to eq("/client/v4/zones/#{zone_id}/custom_hostnames")
      expect(JSON.parse(post.body)).to eq(
        'hostname' => 'example.com',
        'ssl' => { 'method' => 'http', 'type' => 'dv' }
      )
      expect(post['Authorization']).to eq("Bearer #{token}")
    end

    it 'looks the hostname up again when Cloudflare reports a duplicate' do
      existing = hostname_payload('www.example.com', id: 'host-www', status: 'active', ssl_status: 'active')
      calls = 0
      allow(http).to receive(:request) do |request|
        calls += 1
        if request.is_a?(Net::HTTP::Post)
          json_response(409, { 'success' => false, 'errors' => [{ 'code' => 1406, 'message' => 'Duplicate custom hostname found.' }] })
        else
          json_response(200, { 'success' => true, 'result' => calls == 1 ? [] : [existing] })
        end
      end

      result = service.add_domain('www.example.com')

      expect(result['id']).to eq('host-www')
      expect(result['verified']).to be true
      expect(result['verificationStatus']).to eq('verified')
    end
  end

  describe '#verify_domain' do
    it 'is verified only when the hostname and the certificate are both active' do
      allow(http).to receive(:request).and_return(
        json_response(200, {
          'success' => true,
          'result' => hostname_payload('example.com', id: 'host-1', status: 'active', ssl_status: 'active')
        })
      )

      expect(service.verify_domain('host-1')).to include('verified' => true, 'ssl_status' => 'active')
    end

    it 'is not verified while the certificate is still pending' do
      allow(http).to receive(:request).and_return(
        json_response(200, {
          'success' => true,
          'result' => hostname_payload('example.com', id: 'host-1', status: 'active', ssl_status: 'pending_validation')
        })
      )

      result = service.verify_domain('host-1')
      expect(result['verified']).to be false
      expect(result['hostname_status']).to eq('active')
      expect(result['ssl_status']).to eq('pending_validation')
    end
  end

  describe '#pair_verification' do
    it 'requires both apex and www to be active with certificates' do
      payloads = {
        'example.com' => hostname_payload('example.com', id: 'apex-id', status: 'active', ssl_status: 'active'),
        'www.example.com' => hostname_payload('www.example.com', id: 'www-id', status: 'pending', ssl_status: 'pending_validation')
      }
      allow(http).to receive(:request) do |request|
        if (name = hostname_from(request))
          row = payloads[name]
          json_response(200, { 'success' => true, 'result' => row ? [row] : [] })
        else
          id = request.path.split('/').last
          row = payloads.values.find { |payload| payload['id'] == id }
          json_response(200, { 'success' => true, 'result' => row })
        end
      end

      result = service.pair_verification('www.example.com')

      expect(result[:found]).to be true
      expect(result[:verified]).to be false
      expect(result[:error]).to include('www.example.com')
    end
  end

  describe '#remove_domain' do
    it 'deletes the custom hostname' do
      requests = []
      allow(http).to receive(:request) do |request|
        requests << request
        json_response(200, { 'success' => true, 'result' => { 'id' => 'host-1' } })
      end

      expect(service.remove_domain('host-1')).to be true
      expect(requests.first).to be_a(Net::HTTP::Delete)
      expect(requests.first.path).to eq("/client/v4/zones/#{zone_id}/custom_hostnames/host-1")
    end

    it 'treats an already-deleted hostname as success' do
      allow(http).to receive(:request).and_return(
        json_response(404, { 'success' => false, 'errors' => [{ 'message' => 'not found' }] })
      )

      expect(service.remove_domain('missing')).to be true
    end
  end

  describe '#txt_records_for' do
    it 'collects ownership and certificate TXT records and ignores HTTP challenges' do
      apex = hostname_payload(
        'example.com',
        id: 'apex-id',
        extra: {
          ownership_verification: {
            'type' => 'txt',
            'name' => '_cf-custom-hostname.example.com',
            'value' => 'ownership-token'
          },
          validation_records: [
            { 'txt_name' => '_acme-challenge.example.com', 'txt_value' => 'cert-token' },
            { 'http_url' => 'http://example.com/.well-known/cf', 'http_body' => 'ignore-me' }
          ]
        }
      )
      allow(http).to receive(:request) do |request|
        row = hostname_from(request) == 'example.com' ? apex : nil
        json_response(200, { 'success' => true, 'result' => row ? [row] : [] })
      end

      records = service.txt_records_for('example.com')

      expect(records).to include(
        hash_including(name: '_cf-custom-hostname.example.com', value: 'ownership-token', purpose: 'ownership'),
        hash_including(name: '_acme-challenge.example.com', value: 'cert-token', purpose: 'certificate')
      )
      expect(records.map { |record| record[:value] }).not_to include('ignore-me')
    end
  end

  describe 'token handling' do
    it 'never logs the API token' do
      messages = []
      %i[debug info warn error].each do |level|
        allow(Rails.logger).to receive(level) { |*args| messages << args.map(&:to_s).join }
      end
      allow(http).to receive(:request).and_raise(StandardError, "authorization failed for #{token}")

      expect { service.add_domain('example.com') }.to raise_error(described_class::CloudflareApiError)
      expect(messages.join).not_to include(token)
      expect(messages.join).to include('[redacted]')
    end
  end
end
