# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AllowedHostService do
  describe '.primary_domain' do
    it 'returns bizblasts.com in production' do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
      expect(described_class.primary_domain).to eq('bizblasts.com')
    end

    it 'returns example.com in test' do
      expect(described_class.primary_domain).to eq('example.com')
    end

    it 'returns lvh.me in development' do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
      expect(described_class.primary_domain).to eq('lvh.me')
    end
  end

  describe '.main_domains' do
    context 'in production' do
      before { allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production')) }

      it 'includes bizblasts.com' do
        expect(described_class.main_domains).to include('bizblasts.com')
      end

      it 'includes www.bizblasts.com' do
        expect(described_class.main_domains).to include('www.bizblasts.com')
      end

      it 'includes bizblasts.onrender.com' do
        expect(described_class.main_domains).to include('bizblasts.onrender.com')
      end
    end

    context 'in test' do
      it 'includes example.com' do
        expect(described_class.main_domains).to include('example.com')
      end

      it 'includes test.host' do
        expect(described_class.main_domains).to include('test.host')
      end
    end

    context 'in development' do
      before { allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development')) }

      it 'includes lvh.me' do
        expect(described_class.main_domains).to include('lvh.me')
      end

      it 'includes localhost' do
        expect(described_class.main_domains).to include('localhost')
      end
    end
  end

  describe '.main_domain?' do
    it 'returns true for example.com' do
      expect(described_class.main_domain?('example.com')).to be true
    end

    it 'returns true for www.example.com' do
      expect(described_class.main_domain?('www.example.com')).to be true
    end

    it 'returns false for tenant.example.com' do
      expect(described_class.main_domain?('tenant.example.com')).to be false
    end

    it 'returns false for blank host' do
      expect(described_class.main_domain?('')).to be false
      expect(described_class.main_domain?(nil)).to be false
    end

    it 'normalizes host to lowercase' do
      expect(described_class.main_domain?('EXAMPLE.COM')).to be true
    end

    it 'removes port numbers' do
      expect(described_class.main_domain?('example.com:3000')).to be true
    end
  end

  describe '.valid_platform_subdomain?' do
    context 'in test environment' do
      it 'returns true for valid subdomain on example.com' do
        expect(described_class.valid_platform_subdomain?('tenant.example.com')).to be true
      end

      it 'returns true for subdomain with hyphens' do
        expect(described_class.valid_platform_subdomain?('my-business.example.com')).to be true
      end

      it 'returns true for subdomain with numbers' do
        expect(described_class.valid_platform_subdomain?('tenant123.example.com')).to be true
      end

      # Security test cases - these should all FAIL
      it 'returns false for evil-example.com (missing dot)' do
        expect(described_class.valid_platform_subdomain?('evil-example.com')).to be false
      end

      it 'returns false for myexample.com.evil.org (domain in middle)' do
        expect(described_class.valid_platform_subdomain?('myexample.com.evil.org')).to be false
      end

      it 'returns false for example.com (main domain, not subdomain)' do
        expect(described_class.valid_platform_subdomain?('example.com')).to be false
      end

      it 'returns false for www.example.com (www is not a tenant)' do
        expect(described_class.valid_platform_subdomain?('www.example.com')).to be false
      end

      it 'returns false for multi-level subdomains' do
        expect(described_class.valid_platform_subdomain?('sub.tenant.example.com')).to be false
      end

      it 'returns false for blank host' do
        expect(described_class.valid_platform_subdomain?('')).to be false
        expect(described_class.valid_platform_subdomain?(nil)).to be false
      end

      it 'normalizes case' do
        expect(described_class.valid_platform_subdomain?('TENANT.EXAMPLE.COM')).to be true
      end

      it 'handles ports in development/test' do
        expect(described_class.valid_platform_subdomain?('tenant.example.com:3000')).to be true
      end
    end

    context 'in production environment' do
      before { allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production')) }

      it 'returns true for tenant.bizblasts.com' do
        expect(described_class.valid_platform_subdomain?('tenant.bizblasts.com')).to be true
      end

      it 'returns false for evil-bizblasts.com' do
        expect(described_class.valid_platform_subdomain?('evil-bizblasts.com')).to be false
      end

      it 'returns false for mybizblasts.com.evil.org' do
        expect(described_class.valid_platform_subdomain?('mybizblasts.com.evil.org')).to be false
      end

      it 'returns false for bizblasts.com' do
        expect(described_class.valid_platform_subdomain?('bizblasts.com')).to be false
      end
    end

    context 'in development environment' do
      before { allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development')) }

      it 'returns true for tenant.lvh.me' do
        expect(described_class.valid_platform_subdomain?('tenant.lvh.me')).to be true
      end

      it 'returns false for evil-lvh.me' do
        expect(described_class.valid_platform_subdomain?('evil-lvh.me')).to be false
      end

      it 'returns false for mylvh.me.evil.org' do
        expect(described_class.valid_platform_subdomain?('mylvh.me.evil.org')).to be false
      end

      it 'handles ports correctly' do
        expect(described_class.valid_platform_subdomain?('tenant.lvh.me:3000')).to be true
      end
    end
  end

  describe '.valid_custom_domain?' do
    let!(:business_with_custom_domain) do
      create(:business, :with_custom_domain,
             hostname: 'mybusiness.com',
             status: 'cname_active')
    end

    let!(:business_with_www_domain) do
      create(:business, :with_custom_domain,
             hostname: 'www.anotherbiz.com',
             status: 'cname_monitoring')
    end

    let!(:business_with_inactive_domain) do
      create(:business, :with_custom_domain,
             hostname: 'inactive.com',
             status: 'inactive')
    end

    it 'returns true for registered custom domain' do
      expect(described_class.valid_custom_domain?('mybusiness.com')).to be true
    end

    it 'returns true for custom domain with www' do
      expect(described_class.valid_custom_domain?('www.anotherbiz.com')).to be true
    end

    it 'handles apex/www variations for registered domain' do
      expect(described_class.valid_custom_domain?('anotherbiz.com')).to be true
    end

    it 'returns false for inactive custom domain' do
      expect(described_class.valid_custom_domain?('inactive.com')).to be false
    end

    it 'returns false for non-existent custom domain' do
      expect(described_class.valid_custom_domain?('notregistered.com')).to be false
    end

    it 'returns false for blank host' do
      expect(described_class.valid_custom_domain?('')).to be false
      expect(described_class.valid_custom_domain?(nil)).to be false
    end

    it 'normalizes case' do
      expect(described_class.valid_custom_domain?('MYBUSINESS.COM')).to be true
    end

    it 'handles database errors gracefully' do
      allow(Business).to receive(:where).and_raise(ActiveRecord::StatementInvalid.new('DB error'))
      expect(described_class.valid_custom_domain?('mybusiness.com')).to be false
    end

    context 'when businesses table does not exist' do
      before do
        allow(ActiveRecord::Base.connection).to receive(:table_exists?)
          .with('businesses').and_return(false)
      end

      it 'returns false' do
        expect(described_class.valid_custom_domain?('mybusiness.com')).to be false
      end
    end
  end

  describe '.allowed?' do
    let!(:custom_business) do
      create(:business, :with_custom_domain,
             hostname: 'customdomain.com',
             status: 'cname_active')
    end

    context 'main platform domains' do
      it 'allows example.com' do
        expect(described_class.allowed?('example.com')).to be true
      end

      it 'allows www.example.com' do
        expect(described_class.allowed?('www.example.com')).to be true
      end

      it 'allows test.host' do
        expect(described_class.allowed?('test.host')).to be true
      end
    end

    context 'platform subdomains' do
      it 'allows valid subdomain' do
        expect(described_class.allowed?('tenant.example.com')).to be true
      end

      it 'allows subdomain with hyphens' do
        expect(described_class.allowed?('my-business.example.com')).to be true
      end

      # Critical security tests
      it 'rejects evil-example.com (bypass attempt)' do
        expect(described_class.allowed?('evil-example.com')).to be false
      end

      it 'rejects myexample.com.evil.org (bypass attempt)' do
        expect(described_class.allowed?('myexample.com.evil.org')).to be false
      end

      it 'rejects multi-level subdomains' do
        expect(described_class.allowed?('sub.tenant.example.com')).to be false
      end
    end

    context 'custom domains' do
      it 'allows registered custom domain' do
        expect(described_class.allowed?('customdomain.com')).to be true
      end

      it 'allows www variant of custom domain' do
        expect(described_class.allowed?('www.customdomain.com')).to be true
      end

      it 'rejects non-registered custom domain' do
        expect(described_class.allowed?('notregistered.com')).to be false
      end
    end

    context 'edge cases' do
      it 'rejects blank host' do
        expect(described_class.allowed?('')).to be false
        expect(described_class.allowed?(nil)).to be false
      end

      it 'normalizes case' do
        expect(described_class.allowed?('EXAMPLE.COM')).to be true
      end

      it 'strips ports' do
        expect(described_class.allowed?('example.com:3000')).to be true
        expect(described_class.allowed?('tenant.example.com:3000')).to be true
      end

      it 'handles whitespace' do
        expect(described_class.allowed?('  example.com  ')).to be true
      end
    end

    context 'production environment' do
      before { allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production')) }

      it 'allows bizblasts.com' do
        expect(described_class.allowed?('bizblasts.com')).to be true
      end

      it 'allows tenant.bizblasts.com' do
        expect(described_class.allowed?('tenant.bizblasts.com')).to be true
      end

      it 'rejects evil-bizblasts.com' do
        expect(described_class.allowed?('evil-bizblasts.com')).to be false
      end

      it 'rejects mybizblasts.com.evil.org' do
        expect(described_class.allowed?('mybizblasts.com.evil.org')).to be false
      end
    end

    context 'development environment' do
      before { allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development')) }

      it 'allows lvh.me' do
        expect(described_class.allowed?('lvh.me')).to be true
      end

      it 'allows localhost' do
        expect(described_class.allowed?('localhost')).to be true
      end

      it 'allows tenant.lvh.me' do
        expect(described_class.allowed?('tenant.lvh.me')).to be true
      end

      it 'allows tenant.lvh.me:3000 with port' do
        expect(described_class.allowed?('tenant.lvh.me:3000')).to be true
      end

      it 'rejects evil-lvh.me' do
        expect(described_class.allowed?('evil-lvh.me')).to be false
      end
    end
  end

  describe 'comprehensive security validation' do
    it 'prevents all known substring bypass techniques' do
      # These are real attack vectors that would bypass .includes('example.com')
      attack_vectors = [
        'evil-example.com',              # Hyphen before domain
        'myexample.com.attacker.com',    # Domain in middle
        'example.com.evil.org',          # Domain as subdomain
        'evilexample.com',               # Concatenated
        'example.commercial',            # Similar TLD
        'sub.sub.example.com',           # Multi-level (not single tenant subdomain)
      ]

      attack_vectors.each do |malicious_host|
        expect(described_class.allowed?(malicious_host)).to be(false),
          -> { "Expected #{malicious_host} to be rejected but it was allowed!" }
      end
    end

    it 'allows all legitimate platform patterns' do
      legitimate_hosts = [
        'example.com',
        'www.example.com',
        'test.host',
        'tenant.example.com',
        'my-business.example.com',
        'tenant123.example.com'
      ]

      legitimate_hosts.each do |legitimate_host|
        expect(described_class.allowed?(legitimate_host)).to be(true),
          -> { "Expected #{legitimate_host} to be allowed but it was rejected!" }
      end
    end
  end

  describe 'caching behavior for custom domains' do
    before do
      # Clear cache before each test
      Rails.cache.clear
    end

    context 'when validating custom domains' do
      let!(:business) do
        create(:business, :with_custom_domain,
               hostname: 'cached-domain.com',
               status: 'cname_active')
      end

      it 'caches custom domain validation results' do
        # First call - should hit database
        expect(Business).to receive(:where).once.and_call_original
        expect(described_class.valid_custom_domain?('cached-domain.com')).to be true

        # Second call - should use cache (no database query)
        expect(Business).not_to receive(:where)
        expect(described_class.valid_custom_domain?('cached-domain.com')).to be true
      end

      it 'caches results for www and apex variations together' do
        # First call with www variant
        expect(Business).to receive(:where).once.and_call_original
        expect(described_class.valid_custom_domain?('www.cached-domain.com')).to be true

        # Second call with apex variant - should use same cache
        expect(Business).not_to receive(:where)
        expect(described_class.valid_custom_domain?('cached-domain.com')).to be true
      end

      it 'cache expires after 5 minutes' do
        # Cache the result
        expect(described_class.valid_custom_domain?('cached-domain.com')).to be true

        # Travel forward 6 minutes
        travel 6.minutes do
          # Should hit database again after cache expiration
          expect(Business).to receive(:where).once.and_call_original
          expect(described_class.valid_custom_domain?('cached-domain.com')).to be true
        end
      end
    end

    context 'cache invalidation' do
      let!(:business) do
        create(:business, :with_custom_domain,
               hostname: 'invalidate-test.com',
               status: 'cname_active')
      end

      it 'invalidates cache when business hostname changes' do
        # Cache the result
        expect(described_class.valid_custom_domain?('invalidate-test.com')).to be true
        expect(described_class.valid_custom_domain?('www.invalidate-test.com')).to be true

        # Change hostname - should trigger cache invalidation
        business.update!(hostname: 'new-domain.com')

        # Old domain should not be in cache anymore
        expect(Business).to receive(:where).and_call_original
        expect(described_class.valid_custom_domain?('invalidate-test.com')).to be false
      end

      it 'invalidates cache when business status changes' do
        # Cache the result
        expect(described_class.valid_custom_domain?('invalidate-test.com')).to be true

        # Change status to inactive - should trigger cache invalidation
        business.update!(status: 'inactive')

        # Should hit database again and return false (inactive not allowed)
        expect(Business).to receive(:where).and_call_original
        expect(described_class.valid_custom_domain?('invalidate-test.com')).to be false
      end

      it 'invalidates cache when host_type changes' do
        # Cache the result
        expect(described_class.valid_custom_domain?('invalidate-test.com')).to be true

        # Change to subdomain type - should trigger cache invalidation
        business.update!(host_type: 'subdomain', subdomain: 'invalidate-test')

        # Should hit database again and return false (not custom_domain anymore)
        expect(Business).to receive(:where).and_call_original
        expect(described_class.valid_custom_domain?('invalidate-test.com')).to be false
      end

      it 'does not invalidate cache for subdomain businesses' do
        subdomain_business = create(:business, hostname: 'subdomain-test', host_type: 'subdomain')

        # Update subdomain business - should NOT trigger cache invalidation
        expect(Rails.cache).not_to receive(:delete_matched)
        subdomain_business.update!(name: 'Updated Name')
      end
    end
  end
end
