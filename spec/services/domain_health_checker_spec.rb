# frozen_string_literal: true

require 'rails_helper'
require 'net/http'

RSpec.describe DomainHealthChecker, type: :service do
  let(:domain) { 'example.com' }
  let(:checker) { described_class.new(domain) }

  describe '#initialize' do
    it 'normalizes domain name' do
      checker = described_class.new('  EXAMPLE.COM  ')
      expect(checker.instance_variable_get(:@domain_name)).to eq('example.com')
    end

    it 'initializes memoization cache' do
      expect(checker.instance_variable_get(:@memoized_results)).to eq({})
    end
  end

  describe '#check_health' do
    let(:mock_http) { instance_double(Net::HTTP) }
    let(:mock_response) { instance_double(Net::HTTPSuccess, code: '200', to_hash: {}) }

    before do
      allow(Net::HTTP).to receive(:new).and_return(mock_http)
      allow(mock_http).to receive(:use_ssl=)
      allow(mock_http).to receive(:open_timeout=)
      allow(mock_http).to receive(:read_timeout=)
      allow(mock_http).to receive(:verify_mode=)
      allow(mock_http).to receive(:request).and_return(mock_response)
    end

    context 'when domain returns HTTP 200' do
      it 'returns healthy status' do
        result = checker.check_health

        expect(result[:healthy]).to be true
        expect(result[:status_code]).to eq(200)
        expect(result[:domain]).to eq('example.com')
        expect(result[:response_time]).to be_a(Float)
        expect(result[:checked_at]).to be_within(1.second).of(Time.current)
      end

      it 'memoizes the result' do
        # First call
        result1 = checker.check_health
        
        # Second call should return memoized result without making HTTP request
        expect(Net::HTTP).not_to receive(:new)
        result2 = checker.check_health
        
        expect(result1).to eq(result2)
      end
    end

    context 'when domain returns non-200 status' do
      let(:mock_response) { instance_double(Net::HTTPNotFound, code: '404', to_hash: {}) }

      it 'returns unhealthy status' do
        result = checker.check_health

        expect(result[:healthy]).to be false
        expect(result[:status_code]).to eq(404)
        expect(result[:error]).to be_nil
      end
    end

    context 'when domain has redirects' do
      let(:mock_redirect_response) { instance_double(Net::HTTPMovedPermanently, code: '301', to_hash: {}) }
      let(:mock_final_response) { instance_double(Net::HTTPSuccess, code: '200', to_hash: {}) }

      before do
        allow(mock_redirect_response).to receive(:is_a?).with(Net::HTTPRedirection).and_return(true)
        allow(mock_redirect_response).to receive(:[]).with('Location').and_return('https://example.com/new-path')
        allow(mock_final_response).to receive(:is_a?).with(Net::HTTPRedirection).and_return(false)
        
        # First call returns redirect, second call returns success
        allow(mock_http).to receive(:request).and_return(mock_redirect_response, mock_final_response)
      end

      it 'follows redirects and returns final status' do
        result = checker.check_health

        expect(result[:healthy]).to be true
        expect(result[:status_code]).to eq(200)
        expect(result[:redirect_count]).to eq(1)
      end
    end

    context 'when request times out' do
      before do
        allow(mock_http).to receive(:request).and_raise(Net::ReadTimeout.new('timeout'))
      end

      it 'returns error result' do
        result = checker.check_health

        expect(result[:healthy]).to be false
        expect(result[:status_code]).to be_nil
        expect(result[:error]).to include('Request timeout')
      end

      it 'memoizes error results' do
        # First call
        result1 = checker.check_health
        
        # Second call should return memoized error
        expect(mock_http).not_to receive(:request)
        result2 = checker.check_health
        
        expect(result1).to eq(result2)
      end
    end

    context 'when DNS resolution fails' do
      before do
        allow(mock_http).to receive(:request).and_raise(SocketError.new('getaddrinfo failed'))
      end

      it 'returns DNS error result' do
        result = checker.check_health

        expect(result[:healthy]).to be false
        expect(result[:error]).to include('DNS/Socket error')
      end
    end

    context 'when SSL error occurs' do
      before do
        # First call (HTTPS) should fail with SSL error
        # Second call (HTTP fallback) should fail with different error (not SSL or redirect)
        call_count = 0
        allow(mock_http).to receive(:request) do
          call_count += 1
          if call_count == 1
            raise OpenSSL::SSL::SSLError.new('certificate verify failed')
          else
            raise SocketError.new('Connection refused') # Non-SSL, non-redirect error
          end
        end
      end

      it 'returns SSL error result when not a propagation delay' do
        result = checker.check_health

        expect(result[:healthy]).to be false
        expect(result[:error]).to include('HTTPS failed (SSL)')
        expect(result[:error]).to include('HTTP failed')
      end
    end

    context 'when too many redirects occur' do
      let(:mock_redirect_response) { instance_double(Net::HTTPMovedPermanently, code: '301', to_hash: {}) }

      before do
        allow(mock_redirect_response).to receive(:is_a?).with(Net::HTTPRedirection).and_return(true)
        allow(mock_redirect_response).to receive(:[]).with('Location').and_return('https://example.com/redirect')
        allow(mock_http).to receive(:request).and_return(mock_redirect_response)
      end

      it 'returns too many redirects error' do
        result = checker.check_health

        expect(result[:healthy]).to be false
        expect(result[:error]).to include('Too many redirects')
      end
    end
  end

  describe '#check_health_both_protocols' do
    it 'checks both HTTP and HTTPS' do
      allow(checker).to receive(:check_health_for_protocol).with('https').and_return({
        healthy: true, status_code: 200, protocol: 'https'
      })
      allow(checker).to receive(:check_health_for_protocol).with('http').and_return({
        healthy: false, status_code: 404, protocol: 'http'
      })

      result = checker.check_health_both_protocols

      expect(result[:healthy]).to be true
      expect(result[:primary_protocol]).to eq('https')
      expect(result[:https_result][:healthy]).to be true
      expect(result[:http_result][:healthy]).to be false
    end

    it 'prefers HTTPS but accepts HTTP if HTTPS fails' do
      allow(checker).to receive(:check_health_for_protocol).with('https').and_return({
        healthy: false, status_code: 404, protocol: 'https'
      })
      allow(checker).to receive(:check_health_for_protocol).with('http').and_return({
        healthy: true, status_code: 200, protocol: 'http'
      })

      result = checker.check_health_both_protocols

      expect(result[:healthy]).to be true
      expect(result[:primary_protocol]).to eq('http')
    end
  end

  describe 'constants' do
    it 'has appropriate timeout settings' do
      expect(described_class::REQUEST_TIMEOUT).to eq(3)
      expect(described_class::MAX_REDIRECTS).to eq(3)
    end
  end
end
