# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DomainSecurity do
  describe '.platform_domain' do
    after do
      # Clear memoization after each test
      DomainSecurity.instance_variable_set(:@platform_domain, nil)
      DomainSecurity.instance_variable_set(:@render_domain, nil)
    end

    it 'returns bizblasts.com in production' do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
      # Clear cached value before test
      DomainSecurity.instance_variable_set(:@platform_domain, nil)
      expect(DomainSecurity.platform_domain).to eq('bizblasts.com')
    end

    it 'returns lvh.me in development' do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
      # Clear cached value before test
      DomainSecurity.instance_variable_set(:@platform_domain, nil)
      expect(DomainSecurity.platform_domain).to eq('lvh.me')
    end

    it 'returns lvh.me in test' do
      expect(DomainSecurity.platform_domain).to eq('lvh.me')
    end
  end

  describe '.valid_platform_domain?' do
    context 'with valid platform domains' do
      it 'accepts exact match of platform domain' do
        expect(DomainSecurity.valid_platform_domain?('lvh.me')).to be true
      end

      it 'accepts www variant' do
        expect(DomainSecurity.valid_platform_domain?('www.lvh.me')).to be true
      end

      it 'accepts subdomains' do
        expect(DomainSecurity.valid_platform_domain?('salon.lvh.me')).to be true
        expect(DomainSecurity.valid_platform_domain?('myspa.lvh.me')).to be true
      end

      it 'accepts multi-level subdomains' do
        expect(DomainSecurity.valid_platform_domain?('sub.domain.lvh.me')).to be true
      end

      it 'is case insensitive' do
        expect(DomainSecurity.valid_platform_domain?('SALON.LVH.ME')).to be true
        expect(DomainSecurity.valid_platform_domain?('Salon.Lvh.Me')).to be true
      end
    end

    context 'with invalid domains (security tests)' do
      it 'rejects domain spoofing attempts' do
        expect(DomainSecurity.valid_platform_domain?('lvh.me.evil.com')).to be false
        expect(DomainSecurity.valid_platform_domain?('bizblasts.com.evil.com')).to be false
      end

      it 'rejects similar-looking domains' do
        expect(DomainSecurity.valid_platform_domain?('evil-lvh.me')).to be false
        expect(DomainSecurity.valid_platform_domain?('mylvh.me')).to be false
        expect(DomainSecurity.valid_platform_domain?('lvhme.com')).to be false
      end

      it 'rejects domains containing platform domain as substring' do
        expect(DomainSecurity.valid_platform_domain?('evillvh.me.com')).to be false
        expect(DomainSecurity.valid_platform_domain?('notlvh.me')).to be false
      end

      it 'rejects completely unrelated domains' do
        expect(DomainSecurity.valid_platform_domain?('google.com')).to be false
        expect(DomainSecurity.valid_platform_domain?('example.com')).to be false
        expect(DomainSecurity.valid_platform_domain?('attacker.net')).to be false
      end

      it 'rejects nil and empty strings' do
        expect(DomainSecurity.valid_platform_domain?(nil)).to be false
        expect(DomainSecurity.valid_platform_domain?('')).to be false
        expect(DomainSecurity.valid_platform_domain?('   ')).to be false
      end
    end

    context 'in production environment' do
      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
        # Clear cached platform domain
        DomainSecurity.instance_variable_set(:@platform_domain, nil)
      end

      after do
        # Reset to test environment
        allow(Rails).to receive(:env).and_call_original
        DomainSecurity.instance_variable_set(:@platform_domain, nil)
      end

      it 'accepts bizblasts.com domains' do
        expect(DomainSecurity.valid_platform_domain?('bizblasts.com')).to be true
        expect(DomainSecurity.valid_platform_domain?('salon.bizblasts.com')).to be true
      end

      it 'accepts render domain' do
        expect(DomainSecurity.valid_platform_domain?('bizblasts.onrender.com')).to be true
      end

      it 'rejects bizblasts.com spoofing' do
        expect(DomainSecurity.valid_platform_domain?('bizblasts.com.evil.com')).to be false
        expect(DomainSecurity.valid_platform_domain?('mybizblasts.com')).to be false
      end
    end
  end

  describe '.valid_custom_domain?' do
    let!(:verified_business) do
      create(:business,
             host_type: 'custom_domain',
             hostname: 'mysalon.com',
             status: 'cname_active',
             domain_health_verified: true)
    end

    let!(:unverified_business) do
      create(:business,
             host_type: 'custom_domain',
             hostname: 'pending.com',
             status: 'cname_pending',
             domain_health_verified: false)
    end

    let!(:subdomain_business) do
      create(:business,
             host_type: 'subdomain',
             hostname: 'testsalon',
             subdomain: 'testsalon')
    end

    it 'returns true for verified custom domains' do
      expect(DomainSecurity.valid_custom_domain?('mysalon.com')).to be true
    end

    it 'is case insensitive' do
      expect(DomainSecurity.valid_custom_domain?('MySalon.Com')).to be true
      expect(DomainSecurity.valid_custom_domain?('MYSALON.COM')).to be true
    end

    it 'returns false for unverified custom domains' do
      expect(DomainSecurity.valid_custom_domain?('pending.com')).to be false
    end

    it 'returns false for subdomain businesses' do
      expect(DomainSecurity.valid_custom_domain?('testsalon')).to be false
    end

    it 'returns false for non-existent domains' do
      expect(DomainSecurity.valid_custom_domain?('nonexistent.com')).to be false
    end

    it 'returns false for nil and empty strings' do
      expect(DomainSecurity.valid_custom_domain?(nil)).to be false
      expect(DomainSecurity.valid_custom_domain?('')).to be false
    end
  end

  describe '.valid_cors_origin?' do
    let!(:verified_custom_domain) do
      create(:business,
             host_type: 'custom_domain',
             hostname: 'verified.com',
             status: 'cname_active',
             domain_health_verified: true)
    end

    context 'with platform domain origins' do
      it 'accepts platform domain origins' do
        expect(DomainSecurity.valid_cors_origin?('https://lvh.me')).to be true
        expect(DomainSecurity.valid_cors_origin?('http://lvh.me')).to be true
      end

      it 'accepts subdomain origins' do
        expect(DomainSecurity.valid_cors_origin?('https://salon.lvh.me')).to be true
        expect(DomainSecurity.valid_cors_origin?('http://test.lvh.me:3000')).to be true
      end

      it 'accepts www variant' do
        expect(DomainSecurity.valid_cors_origin?('https://www.lvh.me')).to be true
      end
    end

    context 'with custom domain origins' do
      it 'accepts verified custom domain origins' do
        expect(DomainSecurity.valid_cors_origin?('https://verified.com')).to be true
        expect(DomainSecurity.valid_cors_origin?('http://verified.com')).to be true
      end

      it 'rejects unverified custom domains' do
        expect(DomainSecurity.valid_cors_origin?('https://unverified.com')).to be false
      end
    end

    context 'with malicious origins' do
      it 'rejects domain spoofing attempts' do
        expect(DomainSecurity.valid_cors_origin?('https://lvh.me.evil.com')).to be false
        expect(DomainSecurity.valid_cors_origin?('http://bizblasts.com.attacker.net')).to be false
      end

      it 'rejects similar-looking domains' do
        expect(DomainSecurity.valid_cors_origin?('https://mylvh.me')).to be false
        expect(DomainSecurity.valid_cors_origin?('http://evil-lvh.me')).to be false
      end

      it 'rejects invalid URIs' do
        expect(DomainSecurity.valid_cors_origin?('not a uri')).to be false
        expect(DomainSecurity.valid_cors_origin?('javascript:alert(1)')).to be false
      end

      it 'rejects nil and empty origins' do
        expect(DomainSecurity.valid_cors_origin?(nil)).to be false
        expect(DomainSecurity.valid_cors_origin?('')).to be false
      end
    end
  end

  describe '.allowed_cors_origins' do
    let!(:custom_domain1) do
      create(:business,
             host_type: 'custom_domain',
             hostname: 'salon.com',
             status: 'cname_active',
             domain_health_verified: true)
    end

    let!(:custom_domain2) do
      create(:business,
             host_type: 'custom_domain',
             hostname: 'spa.com',
             status: 'cname_active',
             domain_health_verified: true)
    end

    before do
      # Clear cache before each test
      DomainSecurity.clear_origins_cache
    end

    it 'includes platform domain origins' do
      origins = DomainSecurity.allowed_cors_origins
      expect(origins).to include('https://lvh.me')
      expect(origins).to include('http://lvh.me')
      expect(origins).to include('https://www.lvh.me')
      expect(origins).to include('http://www.lvh.me')
    end

    it 'includes subdomain pattern matchers' do
      origins = DomainSecurity.allowed_cors_origins
      subdomain_patterns = origins.select { |o| o.is_a?(Regexp) }
      expect(subdomain_patterns).not_to be_empty

      # Test pattern matching
      subdomain_pattern = subdomain_patterns.find { |p| p.match?('https://test.lvh.me') }
      expect(subdomain_pattern).to be_present
    end

    context 'subdomain regex validation' do
      let(:origins) { DomainSecurity.allowed_cors_origins }
      let(:subdomain_pattern) { origins.find { |o| o.is_a?(Regexp) && o.match?('https://test.lvh.me') } }

      it 'accepts valid single-label subdomains' do
        expect(subdomain_pattern.match?('https://salon.lvh.me')).to be true
        expect(subdomain_pattern.match?('https://myspa.lvh.me')).to be true
        expect(subdomain_pattern.match?('https://test123.lvh.me')).to be true
        expect(subdomain_pattern.match?('https://a.lvh.me')).to be true  # Single character
      end

      it 'accepts valid multi-level subdomains' do
        expect(subdomain_pattern.match?('https://api.v1.lvh.me')).to be true
        expect(subdomain_pattern.match?('https://staging.api.lvh.me')).to be true
        expect(subdomain_pattern.match?('https://a.b.c.lvh.me')).to be true
      end

      it 'accepts valid subdomains with hyphens in middle' do
        expect(subdomain_pattern.match?('https://my-salon.lvh.me')).to be true
        expect(subdomain_pattern.match?('https://test-api-v2.lvh.me')).to be true
        expect(subdomain_pattern.match?('https://api-v1.staging.lvh.me')).to be true
      end

      it 'accepts subdomains with port numbers' do
        expect(subdomain_pattern.match?('https://salon.lvh.me:3000')).to be true
        expect(subdomain_pattern.match?('https://api.v1.lvh.me:8080')).to be true
      end

      it 'rejects subdomains with leading hyphens' do
        expect(subdomain_pattern.match?('https://-salon.lvh.me')).to be false
        expect(subdomain_pattern.match?('https://-test.lvh.me')).to be false
      end

      it 'rejects subdomains with trailing hyphens' do
        expect(subdomain_pattern.match?('https://salon-.lvh.me')).to be false
        expect(subdomain_pattern.match?('https://test-.lvh.me')).to be false
      end

      it 'accepts subdomains with consecutive hyphens (valid per RFC 1123)' do
        # Note: While uncommon, consecutive hyphens are technically valid in DNS
        expect(subdomain_pattern.match?('https://sal--on.lvh.me')).to be true
        expect(subdomain_pattern.match?('https://test--api.lvh.me')).to be true
      end

      it 'rejects subdomain labels starting with hyphens in multi-level' do
        expect(subdomain_pattern.match?('https://-api.staging.lvh.me')).to be false
        expect(subdomain_pattern.match?('https://api.-staging.lvh.me')).to be false
      end

      it 'rejects subdomain labels ending with hyphens in multi-level' do
        expect(subdomain_pattern.match?('https://api-.staging.lvh.me')).to be false
        expect(subdomain_pattern.match?('https://api.staging-.lvh.me')).to be false
      end

      it 'accepts both http and https protocols' do
        http_pattern = origins.find { |o| o.is_a?(Regexp) && o.match?('http://test.lvh.me') }
        expect(http_pattern.match?('http://salon.lvh.me')).to be true
        expect(http_pattern.match?('http://api.v1.lvh.me')).to be true
      end

      it 'rejects non-platform domains' do
        expect(subdomain_pattern.match?('https://evil.com')).to be false
        expect(subdomain_pattern.match?('https://lvh.me.evil.com')).to be false
      end
    end

    it 'includes verified custom domains' do
      origins = DomainSecurity.allowed_cors_origins
      expect(origins).to include('https://salon.com')
      expect(origins).to include('https://www.salon.com')
      expect(origins).to include('https://spa.com')
      expect(origins).to include('https://www.spa.com')
    end

    it 'does not include unverified custom domains' do
      unverified = create(:business,
                         host_type: 'custom_domain',
                         hostname: 'unverified.com',
                         status: 'cname_pending',
                         domain_health_verified: false)

      DomainSecurity.clear_origins_cache # Clear cache to pick up new business
      origins = DomainSecurity.allowed_cors_origins
      expect(origins).not_to include('https://unverified.com')
    end

    it 'returns unique origins only' do
      origins = DomainSecurity.allowed_cors_origins
      expect(origins.length).to eq(origins.uniq.length)
    end

    it 'handles database errors gracefully' do
      allow(Business).to receive(:where).and_raise(StandardError.new('DB error'))

      # Should return basic platform domains even if DB query fails
      origins = DomainSecurity.allowed_cors_origins
      expect(origins).to include('https://lvh.me')
      expect(origins).to include('http://lvh.me')
    end

    it 'caches results for performance' do
      # First call should query database
      expect(DomainSecurity).to receive(:build_allowed_origins).once.and_call_original

      # These calls should use cached results
      3.times { DomainSecurity.allowed_cors_origins }
    end

    it 'cache expires after TTL' do
      # Get initial cached value
      first_result = DomainSecurity.allowed_cors_origins

      # Manually expire cache
      Rails.cache.delete('domain_security:allowed_cors_origins')

      # Should rebuild
      expect(DomainSecurity).to receive(:build_allowed_origins).once.and_call_original
      DomainSecurity.allowed_cors_origins
    end
  end

  describe '.clear_origins_cache' do
    it 'clears the cached origins' do
      # Populate cache
      DomainSecurity.allowed_cors_origins

      # Clear cache
      DomainSecurity.clear_origins_cache

      # Next call should rebuild (not use cache)
      expect(DomainSecurity).to receive(:build_allowed_origins).once.and_call_original
      DomainSecurity.allowed_cors_origins
    end

    it 'handles cache clearing errors gracefully' do
      allow(Rails.cache).to receive(:delete).and_raise(StandardError.new('Cache error'))

      # Should not raise error
      expect { DomainSecurity.clear_origins_cache }.not_to raise_error
    end
  end

  describe '.sanitize_hostname' do
    it 'normalizes hostnames to lowercase' do
      expect(DomainSecurity.sanitize_hostname('EXAMPLE.COM')).to eq('example.com')
    end

    it 'removes dangerous characters' do
      expect(DomainSecurity.sanitize_hostname('evil<script>.com')).to eq('evilscript.com')
      expect(DomainSecurity.sanitize_hostname('bad@host.com')).to eq('badhost.com')
    end

    it 'allows alphanumeric, dots, and hyphens' do
      expect(DomainSecurity.sanitize_hostname('my-site123.example.com')).to eq('my-site123.example.com')
    end

    it 'removes consecutive dots' do
      expect(DomainSecurity.sanitize_hostname('bad..host.com')).to eq('bad.host.com')
    end

    it 'removes consecutive hyphens' do
      expect(DomainSecurity.sanitize_hostname('bad--host.com')).to eq('bad-host.com')
    end

    it 'handles nil and empty strings' do
      expect(DomainSecurity.sanitize_hostname(nil)).to eq('')
      expect(DomainSecurity.sanitize_hostname('')).to eq('')
      expect(DomainSecurity.sanitize_hostname('   ')).to eq('')
    end
  end

  describe '.main_domain_request?' do
    it 'returns true for main domain' do
      request = double('request', host: 'lvh.me')
      expect(DomainSecurity.main_domain_request?(request)).to be true
    end

    it 'returns true for www variant' do
      request = double('request', host: 'www.lvh.me')
      expect(DomainSecurity.main_domain_request?(request)).to be true
    end

    it 'returns false for subdomains' do
      request = double('request', host: 'salon.lvh.me')
      expect(DomainSecurity.main_domain_request?(request)).to be false
    end

    it 'returns false for custom domains' do
      request = double('request', host: 'example.com')
      expect(DomainSecurity.main_domain_request?(request)).to be false
    end

    it 'handles nil request' do
      expect(DomainSecurity.main_domain_request?(nil)).to be false
    end
  end

  describe '.extract_subdomain' do
    it 'extracts subdomain from valid platform domain' do
      expect(DomainSecurity.extract_subdomain('salon.lvh.me')).to eq('salon')
      expect(DomainSecurity.extract_subdomain('myspa.lvh.me')).to eq('myspa')
    end

    it 'returns nil for main domain' do
      expect(DomainSecurity.extract_subdomain('lvh.me')).to be_nil
    end

    it 'returns nil for www subdomain' do
      expect(DomainSecurity.extract_subdomain('www.lvh.me')).to be_nil
    end

    it 'returns nil for invalid domains' do
      expect(DomainSecurity.extract_subdomain('example.com')).to be_nil
      expect(DomainSecurity.extract_subdomain('lvh.me.evil.com')).to be_nil
    end

    it 'handles multi-level subdomains' do
      expect(DomainSecurity.extract_subdomain('sub.domain.lvh.me')).to eq('sub.domain')
    end
  end
end
