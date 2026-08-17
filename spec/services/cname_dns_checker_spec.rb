# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CnameDnsChecker, type: :service do
  let(:domain_name) { 'example.com' }
  let(:checker) { described_class.new(domain_name) }
  let(:expected_target) { 'localhost' }

  before do
    allow(Rails.env).to receive(:production?).and_return(false)

    # These examples stub only the CNAME lookup. In caddy mode the checker
    # resolves apex A records instead (cname_dns_checker.rb:26/31/261), which
    # this file does not stub. It got render mode for free while DomainProvider
    # defaulted to 'render'; the default is now 'caddy', so pin it explicitly.
    #
    # The caddy apex-A path -- the one production actually takes -- is covered
    # by the 'caddy mode' block at the bottom of this file. This pin scopes only
    # the render-mode examples above it.
    allow(DomainProvider).to receive(:provider_name).and_return('render')
  end

  describe '#initialize' do
    it 'initializes with domain name' do
      expect(checker.instance_variable_get(:@domain_name)).to eq(domain_name)
    end

    it 'normalizes domain name' do
      checker = described_class.new('  EXAMPLE.COM  ')
      expect(checker.instance_variable_get(:@domain_name)).to eq('example.com')
    end

    it 'creates DNS resolver' do
      expect(checker.instance_variable_get(:@resolver)).to be_a(Resolv::DNS)
    end
  end

  describe '#verify_cname' do
    let(:resolver) { instance_double(Resolv::DNS) }
    let(:cname_record) { instance_double(Resolv::DNS::Resource::IN::CNAME, name: Resolv::DNS::Name.create("#{expected_target}.")) }

    before do
      checker.instance_variable_set(:@resolver, resolver)
      allow(resolver).to receive(:close)
    end

    context 'when CNAME is correctly configured' do
      before do
        allow(resolver).to receive(:getresources)
          .with(domain_name, Resolv::DNS::Resource::IN::CNAME)
          .and_return([cname_record])
      end

      it 'returns verified true' do
        result = checker.verify_cname

        expect(result[:verified]).to be true
        expect(result[:target]).to eq(expected_target)
        expect(result[:expected_target]).to eq(expected_target)
        expect(result[:domain]).to eq(domain_name)
      end
    end

    context 'when CNAME points to wrong target' do
      let(:wrong_cname) { instance_double(Resolv::DNS::Resource::IN::CNAME, name: Resolv::DNS::Name.create('wrong-target.com.')) }

      before do
        allow(resolver).to receive(:getresources)
          .with(domain_name, Resolv::DNS::Resource::IN::CNAME)
          .and_return([wrong_cname])
      end

      it 'returns verified false' do
        result = checker.verify_cname

        expect(result[:verified]).to be false
        expect(result[:target]).to eq('wrong-target.com')
        expect(result[:expected_target]).to eq(expected_target)
      end
    end

    context 'when no CNAME record exists' do
      before do
        allow(resolver).to receive(:getresources)
          .with(domain_name, Resolv::DNS::Resource::IN::CNAME)
          .and_return([])
        # Also stub A-record lookup invoked by apex check
        allow(resolver).to receive(:getresources)
          .with(domain_name, Resolv::DNS::Resource::IN::A)
          .and_return([])
      end

      it 'returns verified false with error' do
        result = checker.verify_cname

        expect(result[:verified]).to be false
        expect(result[:target]).to be_nil
        expect(result[:error]).to eq('No CNAME record found')
      end
    end

    context 'when no CNAME but apex A record matches Render' do
      before do
        allow(resolver).to receive(:getresources)
          .with(domain_name, Resolv::DNS::Resource::IN::CNAME)
          .and_return([])
        a_record = instance_double(Resolv::DNS::Resource::IN::A, address: IPAddr.new('216.24.57.1'))
        allow(resolver).to receive(:getresources)
          .with(domain_name, Resolv::DNS::Resource::IN::A)
          .and_return([a_record])
      end

      it 'returns verified true using apex A record' do
        result = checker.verify_cname

        expect(result[:verified]).to be true
        expect(result[:target]).to eq('216.24.57.1')
        expect(result[:error]).to be_nil
      end
    end

    context 'when DNS resolution fails' do
      before do
        allow(resolver).to receive(:getresources).with(domain_name, Resolv::DNS::Resource::IN::CNAME)
          .and_raise(Resolv::ResolvError.new('DNS resolution failed'))
      end

      it 'returns verified false with error' do
        result = checker.verify_cname

        expect(result[:verified]).to be false
        expect(result[:error]).to include('DNS resolution failed')
      end
    end

    context 'in development environment' do
      before do
        allow(Rails.env).to receive(:production?).and_return(false)
        allow(resolver).to receive(:getresources)
          .with(domain_name, Resolv::DNS::Resource::IN::CNAME)
          .and_return([instance_double(Resolv::DNS::Resource::IN::CNAME, name: Resolv::DNS::Name.create('localhost.'))])
        # Prevent unexpected A-record lookup stubs in this branch
        allow(resolver).to receive(:getresources)
          .with(domain_name, Resolv::DNS::Resource::IN::A)
          .and_return([])
      end

      it 'accepts localhost as valid target' do
        result = checker.verify_cname

        expect(result[:verified]).to be true
        expect(result[:target]).to eq('localhost')
      end
    end
  end

  describe '#verify_cname_multiple_dns' do
    let(:resolver1) { instance_double(Resolv::DNS) }
    let(:resolver2) { instance_double(Resolv::DNS) }
    let(:resolver3) { instance_double(Resolv::DNS) }

    before do
      allow(Resolv::DNS).to receive(:new).and_call_original
      allow(Resolv::DNS).to receive(:new).with(nameserver: ['8.8.8.8']).and_return(resolver1)
      allow(Resolv::DNS).to receive(:new).with(nameserver: ['1.1.1.1']).and_return(resolver2)
      allow(Resolv::DNS).to receive(:new).with(nameserver: ['208.67.222.222']).and_return(resolver3)

      [resolver1, resolver2, resolver3].each { |r| allow(r).to receive(:close) }
    end

    context 'when all DNS servers return positive results' do
      let(:cname_record) { instance_double(Resolv::DNS::Resource::IN::CNAME, name: Resolv::DNS::Name.create("#{expected_target}.")) }

      before do
        [resolver1, resolver2, resolver3].each do |resolver|
          allow(resolver).to receive(:getresources)
            .with(domain_name, Resolv::DNS::Resource::IN::CNAME)
            .and_return([cname_record])
        end
      end

      it 'returns aggregated positive results' do
        result = checker.verify_cname_multiple_dns

        expect(result[:verified]).to be true
        expect(result[:all_verified]).to be true
        expect(result[:verification_ratio]).to eq('3/3')
        expect(result[:results]).to have_attributes(size: 3)
      end
    end

    context 'when some DNS servers fail' do
      let(:cname_record) { instance_double(Resolv::DNS::Resource::IN::CNAME, name: Resolv::DNS::Name.create("#{expected_target}.")) }

      before do
        allow(resolver1).to receive(:getresources).and_return([cname_record])
        allow(resolver2).to receive(:getresources).and_raise(StandardError.new('DNS timeout'))
        allow(resolver3).to receive(:getresources).and_return([])
      end

      it 'returns mixed results' do
        result = checker.verify_cname_multiple_dns

        expect(result[:verified]).to be true  # At least one verified
        expect(result[:all_verified]).to be false  # Not all verified
        expect(result[:verification_ratio]).to eq('1/3')
      end
    end
  end

  describe '#dns_debug_info' do
    let(:resolver) { instance_double(Resolv::DNS) }

    before do
      checker.instance_variable_set(:@resolver, resolver)
      allow(resolver).to receive(:close)
    end

    it 'returns comprehensive DNS information' do
      # Mock different record types
      allow(resolver).to receive(:getresources).with(domain_name, Resolv::DNS::Resource::IN::A).and_return([])
      allow(resolver).to receive(:getresources).with(domain_name, Resolv::DNS::Resource::IN::CNAME).and_return([])
      allow(resolver).to receive(:getresources).with(domain_name, Resolv::DNS::Resource::IN::AAAA).and_return([])
      allow(resolver).to receive(:getresources).with(domain_name, Resolv::DNS::Resource::IN::MX).and_return([])

      result = checker.dns_debug_info

      expect(result[:domain]).to eq(domain_name)
      expect(result[:records]).to have_key('A')
      expect(result[:records]).to have_key('CNAME')
      expect(result[:records]).to have_key('AAAA')
      expect(result[:records]).to have_key('MX')
    end

    context 'with www subdomain' do
      let(:domain_name) { 'www.example.com' }

      it 'includes root domain check' do
        allow(resolver).to receive(:getresources).and_return([])

        result = checker.dns_debug_info

        expect(result[:root_domain_check]).to be_present
      end
    end
  end

  describe '#domain_resolves?' do
    let(:resolver) { instance_double(Resolv::DNS) }

    before do
      checker.instance_variable_set(:@resolver, resolver)
    end

    context 'when domain resolves to IP addresses' do
      before do
        allow(resolver).to receive(:getaddresses).with(domain_name).and_return(['192.168.1.1', '10.0.0.1'])
      end

      it 'returns true' do
        expect(checker.domain_resolves?).to be true
      end
    end

    context 'when domain does not resolve' do
      before do
        allow(resolver).to receive(:getaddresses).with(domain_name).and_return([])
      end

      it 'returns false' do
        expect(checker.domain_resolves?).to be false
      end
    end

    context 'when DNS lookup fails' do
      before do
        allow(resolver).to receive(:getaddresses).and_raise(StandardError.new('DNS error'))
      end

      it 'returns false' do
        expect(checker.domain_resolves?).to be false
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Caddy-mode verification
  #
  # Everything above pins the provider to 'render'. This block covers the caddy
  # branch -- apex/www A records against BIZBLASTS_PUBLIC_IP, with no
  # CNAME-to-onrender step -- which is what the self-hosted deployment runs.
  # Previously untested.
  # ---------------------------------------------------------------------------
  describe 'caddy mode' do
    let(:public_ip) { '203.0.113.10' }
    let(:resolver) { instance_double(Resolv::DNS) }
    let(:a_record) { instance_double(Resolv::DNS::Resource::IN::A, address: public_ip) }

    before do
      allow(DomainProvider).to receive(:provider_name).and_return('caddy')
      ENV['BIZBLASTS_PUBLIC_IP'] = public_ip
    end

    after { ENV.delete('BIZBLASTS_PUBLIC_IP') }

    describe '.expected_cname_target' do
      # Returning nil is what makes verify_cname skip CNAME resolution entirely.
      it 'is nil, because there is no CNAME step on Caddy' do
        expect(described_class.expected_cname_target).to be_nil
      end
    end

    describe '.expected_apex_ip' do
      it 'is the configured public IP' do
        expect(described_class.expected_apex_ip).to eq(public_ip)
      end

      it 'strips surrounding whitespace so it matches what DomainMailer emits' do
        ENV['BIZBLASTS_PUBLIC_IP'] = "  #{public_ip}\n"
        expect(described_class.expected_apex_ip).to eq(public_ip)
      end

      it 'falls back to a live bizblasts.com A lookup when the var is unset' do
        ENV.delete('BIZBLASTS_PUBLIC_IP')
        allow(described_class).to receive(:resolve_bizblasts_a).and_return('198.51.100.7')

        expect(described_class.expected_apex_ip).to eq('198.51.100.7')
      end
    end

    describe '#verify_cname' do
      let(:checker) { described_class.new(domain_name) }

      before do
        checker.instance_variable_set(:@resolver, resolver)
        allow(resolver).to receive(:close)
      end

      context 'when the A record points at the public IP' do
        before do
          allow(resolver).to receive(:getresources)
            .with(domain_name, Resolv::DNS::Resource::IN::A)
            .and_return([a_record])
        end

        it 'verifies against the A record and reports the IP as the target' do
          result = checker.verify_cname

          expect(result[:verified]).to be true
          expect(result[:target]).to eq(public_ip)
          expect(result[:expected_target]).to eq(public_ip)
          expect(result[:error]).to be_nil
        end

        it 'never performs a CNAME lookup' do
          expect(resolver).not_to receive(:getresources)
            .with(anything, Resolv::DNS::Resource::IN::CNAME)

          checker.verify_cname
        end
      end

      context 'when the A record points somewhere else' do
        before do
          allow(resolver).to receive(:getresources)
            .with(domain_name, Resolv::DNS::Resource::IN::A)
            .and_return([instance_double(Resolv::DNS::Resource::IN::A, address: '198.51.100.99')])
        end

        it 'reports the A-record error rather than the CNAME one' do
          result = checker.verify_cname

          expect(result[:verified]).to be false
          expect(result[:error]).to eq('A-record does not point at BizBlasts public IP')
        end
      end
    end

    describe 'a www host' do
      # On Caddy, www needs its OWN A record: AllowedHostService gates the
      # on_demand_tls handshake per exact host, so accepting the apex's A record
      # on behalf of www would let verification pass and then 404 at handshake.
      # Render's branch deliberately strips the www. prefix instead. Exercised
      # through verify_cname, since the matcher itself is private.
      let(:checker) { described_class.new('www.example.com') }

      before do
        checker.instance_variable_set(:@resolver, resolver)
        allow(resolver).to receive(:close)
      end

      it 'looks up the exact www host rather than the stripped apex' do
        expect(resolver).to receive(:getresources)
          .with('www.example.com', Resolv::DNS::Resource::IN::A)
          .and_return([a_record])
        expect(resolver).not_to receive(:getresources)
          .with('example.com', Resolv::DNS::Resource::IN::A)

        expect(checker.verify_cname[:verified]).to be true
      end

      it 'stays unverified when www has no A record of its own' do
        allow(resolver).to receive(:getresources)
          .with('www.example.com', Resolv::DNS::Resource::IN::A)
          .and_return([])

        result = checker.verify_cname

        expect(result[:verified]).to be false
        expect(result[:error]).to eq('A-record does not point at BizBlasts public IP')
      end
    end
  end
end
