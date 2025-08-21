# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CnameDnsChecker, type: :service do
  let(:domain_name) { 'example.com' }
  let(:checker) { described_class.new(domain_name) }
  let(:expected_target) { 'localhost' }

  before do
    allow(Rails.env).to receive(:production?).and_return(false)
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
      end

      it 'returns verified false with error' do
        result = checker.verify_cname

        expect(result[:verified]).to be false
        expect(result[:target]).to be_nil
        expect(result[:error]).to eq('No CNAME record found')
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
end