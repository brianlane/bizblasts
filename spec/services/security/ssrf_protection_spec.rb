# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Security::SsrfProtection do
  describe '.validate_url!' do
    context 'with valid URLs' do
      it 'accepts valid https URL' do
        expect {
          described_class.validate_url!('https://example.com/path')
        }.not_to raise_error
      end

      it 'accepts https URL with allowed protocols' do
        uri = described_class.validate_url!('https://calendar.google.com/caldav', allowed_protocols: ['https'])
        expect(uri).to be_a(URI::HTTPS)
        expect(uri.host).to eq('calendar.google.com')
      end

      it 'accepts http URL when http is allowed' do
        # Mock DNS resolution for test domain
        allow(Resolv).to receive(:getaddresses).with('caldav.local').and_return(['93.184.216.34'])

        uri = described_class.validate_url!('http://caldav.local/calendar', allowed_protocols: ['http', 'https'])
        expect(uri).to be_a(URI::HTTP)
        expect(uri.host).to eq('caldav.local')
      end

      it 'returns parsed URI object' do
        uri = described_class.validate_url!('https://example.com/path')
        expect(uri).to be_a(URI::HTTPS)
        expect(uri.scheme).to eq('https')
        expect(uri.host).to eq('example.com')
        expect(uri.path).to eq('/path')
      end
    end

    context 'with invalid URLs' do
      it 'rejects blank URL' do
        expect {
          described_class.validate_url!('')
        }.to raise_error(Security::SsrfProtection::SsrfError, /URL cannot be blank/)
      end

      it 'rejects nil URL' do
        expect {
          described_class.validate_url!(nil)
        }.to raise_error(Security::SsrfProtection::SsrfError, /URL cannot be blank/)
      end

      it 'rejects malformed URL' do
        expect {
          described_class.validate_url!('not a valid url')
        }.to raise_error(Security::SsrfProtection::SsrfError, /Invalid URL format/)
      end

      it 'rejects URL without hostname' do
        expect {
          described_class.validate_url!('https://')
        }.to raise_error(Security::SsrfProtection::SsrfError, /must include a hostname/)
      end
    end

    context 'with disallowed protocols' do
      it 'rejects http when only https is allowed' do
        expect {
          described_class.validate_url!('http://example.com', allowed_protocols: ['https'])
        }.to raise_error(Security::SsrfProtection::SsrfError, /Protocol 'http' not allowed/)
      end

      it 'rejects file protocol' do
        expect {
          described_class.validate_url!('file:///etc/passwd', allowed_protocols: ['https'])
        }.to raise_error(Security::SsrfProtection::SsrfError, /Protocol 'file' not allowed/)
      end

      it 'rejects ftp protocol' do
        expect {
          described_class.validate_url!('ftp://example.com', allowed_protocols: ['https'])
        }.to raise_error(Security::SsrfProtection::SsrfError, /Protocol 'ftp' not allowed/)
      end

      it 'rejects gopher protocol' do
        expect {
          described_class.validate_url!('gopher://example.com', allowed_protocols: ['https'])
        }.to raise_error(Security::SsrfProtection::SsrfError, /Protocol 'gopher' not allowed/)
      end
    end

    context 'with private IP addresses' do
      it 'rejects localhost' do
        expect {
          described_class.validate_url!('https://localhost/path')
        }.to raise_error(Security::SsrfProtection::SsrfError, /Access to private IP/)
      end

      it 'rejects 127.0.0.1' do
        expect {
          described_class.validate_url!('https://127.0.0.1/path')
        }.to raise_error(Security::SsrfProtection::SsrfError, /Access to private IP/)
      end

      it 'rejects 10.0.0.0/8 range' do
        expect {
          described_class.validate_url!('https://10.0.0.1/path')
        }.to raise_error(Security::SsrfProtection::SsrfError, /Access to private IP/)
      end

      it 'rejects 172.16.0.0/12 range' do
        expect {
          described_class.validate_url!('https://172.16.0.1/path')
        }.to raise_error(Security::SsrfProtection::SsrfError, /Access to private IP/)
      end

      it 'rejects 192.168.0.0/16 range' do
        expect {
          described_class.validate_url!('https://192.168.1.1/path')
        }.to raise_error(Security::SsrfProtection::SsrfError, /Access to private IP/)
      end

      it 'rejects IPv6 loopback' do
        expect {
          described_class.validate_url!('https://[::1]/path')
        }.to raise_error(Security::SsrfProtection::SsrfError, /Access to private IP/)
      end
    end

    context 'with cloud metadata endpoints' do
      it 'rejects AWS/Azure/GCP metadata IP' do
        expect {
          described_class.validate_url!('http://169.254.169.254/latest/meta-data/', allowed_protocols: ['http', 'https'])
        }.to raise_error(Security::SsrfProtection::SsrfError, /Access to metadata endpoint/)
      end

      it 'rejects GCP metadata hostname' do
        # Mock DNS resolution to avoid actual network call
        allow(Resolv).to receive(:getaddresses).with('metadata.google.internal').and_return(['169.254.169.254'])

        expect {
          described_class.validate_url!('http://metadata.google.internal/', allowed_protocols: ['http', 'https'])
        }.to raise_error(Security::SsrfProtection::SsrfError, /Access to metadata endpoint/)
      end

      it 'rejects Alibaba Cloud metadata IP' do
        expect {
          described_class.validate_url!('http://100.100.100.200/latest/meta-data/', allowed_protocols: ['http', 'https'])
        }.to raise_error(Security::SsrfProtection::SsrfError, /Access to metadata endpoint/)
      end
    end

    context 'with DNS resolution' do
      it 'rejects domain that resolves to private IP' do
        # Mock a domain that resolves to a private IP
        allow(Resolv).to receive(:getaddresses).with('internal.example.com').and_return(['192.168.1.1'])

        expect {
          described_class.validate_url!('https://internal.example.com/path')
        }.to raise_error(Security::SsrfProtection::SsrfError, /Access to private IP/)
      end

      it 'rejects domain that resolves to localhost' do
        allow(Resolv).to receive(:getaddresses).with('localtest.me').and_return(['127.0.0.1'])

        expect {
          described_class.validate_url!('https://localtest.me/path')
        }.to raise_error(Security::SsrfProtection::SsrfError, /Access to private IP/)
      end

      it 'handles DNS resolution errors gracefully' do
        allow(Resolv).to receive(:getaddresses).with('nonexistent.example.invalid').and_raise(Resolv::ResolvError)

        expect {
          described_class.validate_url!('https://nonexistent.example.invalid/path')
        }.to raise_error(Security::SsrfProtection::SsrfError, /Could not resolve hostname/)
      end

      it 'rejects hostname that does not resolve to any IP' do
        allow(Resolv).to receive(:getaddresses).with('empty.example.com').and_return([])

        expect {
          described_class.validate_url!('https://empty.example.com/path')
        }.to raise_error(Security::SsrfProtection::SsrfError, /does not resolve to any IP addresses/)
      end
    end
  end

  describe '.validate_hostname!' do
    it 'accepts valid public hostname' do
      # Mock DNS to return public IP
      allow(Resolv).to receive(:getaddresses).with('example.com').and_return(['93.184.216.34'])

      expect {
        described_class.validate_hostname!('example.com')
      }.not_to raise_error
    end

    it 'rejects metadata endpoint hostname' do
      expect {
        described_class.validate_hostname!('169.254.169.254')
      }.to raise_error(Security::SsrfProtection::SsrfError, /Access to metadata endpoint/)
    end

    it 'rejects hostname resolving to private IP' do
      allow(Resolv).to receive(:getaddresses).with('private.local').and_return(['10.0.0.1'])

      expect {
        described_class.validate_hostname!('private.local')
      }.to raise_error(Security::SsrfProtection::SsrfError, /Access to private IP/)
    end

    it 'rejects hostname with multiple IPs if any is private' do
      # Hostname resolves to both public and private IPs
      allow(Resolv).to receive(:getaddresses).with('mixed.example.com').and_return(['93.184.216.34', '192.168.1.1'])

      expect {
        described_class.validate_hostname!('mixed.example.com')
      }.to raise_error(Security::SsrfProtection::SsrfError, /Access to private IP/)
    end
  end

  describe '.safe_request' do
    it 'validates URL and yields block with URI' do
      # Mock DNS
      allow(Resolv).to receive(:getaddresses).with('example.com').and_return(['93.184.216.34'])

      result = described_class.safe_request('https://example.com/path') do |uri|
        uri.to_s
      end

      expect(result).to eq('https://example.com/path')
    end

    it 'prevents DNS rebinding by double-checking hostname' do
      call_count = 0
      allow(Resolv).to receive(:getaddresses).with('example.com') do
        call_count += 1
        ['93.184.216.34']
      end

      described_class.safe_request('https://example.com/path') do |uri|
        # Block executes
      end

      # Should validate hostname twice (once in validate_url!, once before yield)
      expect(call_count).to eq(2)
    end

    it 'rejects malicious URL even when passed to block' do
      expect {
        described_class.safe_request('https://127.0.0.1/path') do |uri|
          # This block should never execute
          raise 'Block should not execute'
        end
      }.to raise_error(Security::SsrfProtection::SsrfError, /Access to private IP/)
    end

    it 'allows custom protocols in safe_request' do
      allow(Resolv).to receive(:getaddresses).with('caldav.local').and_return(['93.184.216.34'])

      result = described_class.safe_request('http://caldav.local/calendar', allowed_protocols: ['http', 'https']) do |uri|
        uri.scheme
      end

      expect(result).to eq('http')
    end
  end
end
