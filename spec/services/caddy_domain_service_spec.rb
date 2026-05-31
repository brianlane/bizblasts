# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CaddyDomainService, type: :service do
  subject(:service) { described_class.new }

  let(:public_ip) { '198.51.100.42' }

  around do |example|
    original_provider = ENV['BIZBLASTS_DOMAIN_PROVIDER']
    original_ip = ENV['BIZBLASTS_PUBLIC_IP']
    ENV['BIZBLASTS_DOMAIN_PROVIDER'] = 'caddy'
    ENV['BIZBLASTS_PUBLIC_IP'] = public_ip
    example.run
    ENV['BIZBLASTS_DOMAIN_PROVIDER'] = original_provider
    ENV['BIZBLASTS_PUBLIC_IP'] = original_ip
  end

  describe '#list_domains' do
    let!(:apex_business) do
      create(:business,
             host_type: 'custom_domain',
             hostname: 'shop.example.com',
             canonical_preference: 'apex')
    end

    let!(:www_business) do
      create(:business,
             host_type: 'custom_domain',
             hostname: 'www.boutique.example',
             canonical_preference: 'www')
    end

    it 'emits BOTH apex and www variants for every persisted hostname' do
      names = service.list_domains.map { |d| d['name'] }
      expect(names).to include('shop.example.com', 'www.shop.example.com',
                               'boutique.example',  'www.boutique.example')
    end

    it 'returns verified=false so the async verify job will run DNS check' do
      expect(service.list_domains).to all(include('verified' => false))
    end

    it 'find_domain_by_name resolves the www variant of an apex-stored business' do
      expect(service.find_domain_by_name('www.shop.example.com')).not_to be_nil
    end

    it 'find_domain_by_name resolves the apex variant of a www-stored business' do
      expect(service.find_domain_by_name('boutique.example')).not_to be_nil
    end

    it 'skips businesses without a hostname' do
      create(:business, host_type: 'subdomain', hostname: 'sub', subdomain: 'sub')
      names = service.list_domains.map { |d| d['name'] }
      expect(names).not_to include('sub', 'www.sub')
    end
  end

  describe '#verify_domain (strict per-name DNS check)' do
    before do
      # Stub Resolv to control DNS resolution deterministically.
      stub_const('FakeResolver', Class.new do
        def self.records
          @records ||= {}
        end

        def self.set(host, ips)
          records[host] = ips
        end

        def getresources(host, _type)
          (self.class.records[host] || []).map do |ip|
            instance_double(Resolv::DNS::Resource::IN::A, address: IPAddr.new(ip))
          end
        end
      end)

      FakeResolver.records.clear
      allow(Resolv::DNS).to receive(:open).and_yield(FakeResolver.new)
    end

    it 'verifies the EXACT hostname requested (not the apex sibling)' do
      # Apex points at us, www does NOT. www must NOT be reported as verified.
      FakeResolver.set('example.com',     [public_ip])
      FakeResolver.set('www.example.com', ['203.0.113.1']) # wrong IP

      result = service.verify_domain('caddy:www.example.com')

      expect(result['verified']).to be false
    end

    it 'verifies www when www itself points at BizBlasts' do
      FakeResolver.set('www.example.com', [public_ip])

      result = service.verify_domain('caddy:www.example.com')

      expect(result['verified']).to be true
    end

    it 'verifies the apex when the apex points at BizBlasts' do
      FakeResolver.set('example.com', [public_ip])

      result = service.verify_domain('caddy:example.com')

      expect(result['verified']).to be true
    end
  end
end
