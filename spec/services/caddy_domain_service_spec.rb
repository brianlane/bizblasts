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
             canonical_preference: 'apex',
             render_domain_added: true)
    end

    let!(:www_business) do
      create(:business,
             host_type: 'custom_domain',
             hostname: 'www.boutique.example',
             canonical_preference: 'www',
             render_domain_added: true)
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

    it 'skips custom-domain businesses that have not yet completed setup' do
      create(:business,
             host_type: 'custom_domain',
             hostname: 'pending.example.org',
             canonical_preference: 'apex',
             render_domain_added: false)

      names = service.list_domains.map { |d| d['name'] }
      expect(names).not_to include('pending.example.org', 'www.pending.example.org')
    end
  end

  describe '#verify_domain (strict per-name DNS check)' do
    # A-record stand-in: must expose #address that responds to #to_s with
    # the dotted-quad. We use Resolv::IPv4 (the real type the production
    # code receives from Resolv::DNS) so .to_s round-trips correctly.
    let(:fake_records) { Hash.new { |h, k| h[k] = [] } }

    let(:fake_resolver) do
      records = fake_records
      Class.new do
        define_method(:getresources) do |host, _type|
          (records[host] || []).map do |ip|
            Struct.new(:address).new(Resolv::IPv4.create(ip))
          end
        end
      end.new
    end

    before do
      # Production code calls `Resolv::DNS.open { |r| ... }` and expects the
      # method to RETURN whatever the block returns. `and_yield` yields but
      # discards the block's return value, so we route through a block stub.
      allow(Resolv::DNS).to receive(:open) { |&blk| blk.call(fake_resolver) }
    end

    it 'verifies the EXACT hostname requested (not the apex sibling)' do
      # Apex points at us, www does NOT. www must NOT be reported as verified.
      fake_records['example.com']     = [public_ip]
      fake_records['www.example.com'] = ['203.0.113.1'] # wrong IP

      result = service.verify_domain('caddy:www.example.com')

      expect(result['verified']).to be false
    end

    it 'verifies www when www itself points at BizBlasts' do
      fake_records['www.example.com'] = [public_ip]

      result = service.verify_domain('caddy:www.example.com')

      expect(result['verified']).to be true
    end

    it 'verifies the apex when the apex points at BizBlasts' do
      fake_records['example.com'] = [public_ip]

      result = service.verify_domain('caddy:example.com')

      expect(result['verified']).to be true
    end
  end
end
