// Unit tests for TurboTenantHelpers utility class
// Run with: yarn test or npm test

import { TurboTenantHelpers } from '../../app/javascript/modules/turbo_tenant_helpers.js';

// Mock window.location for testing
const mockLocation = (href) => {
  const url = new URL(href);
  Object.defineProperty(window, 'location', {
    value: {
      href: url.href,
      host: url.host,
      hostname: url.hostname,
      port: url.port,
      protocol: url.protocol,
      pathname: url.pathname,
      search: url.search,
      hash: url.hash
    },
    writable: true
  });
};

describe('TurboTenantHelpers', () => {
  beforeEach(() => {
    // Reset DOM
    document.body.innerHTML = '';
    document.head.innerHTML = '';

    // Setup default meta tags for development environment (lvh.me)
    const platformMeta = document.createElement('meta');
    platformMeta.name = 'platform-domain';
    platformMeta.content = 'lvh.me';
    document.head.appendChild(platformMeta);

    const canonicalMeta = document.createElement('meta');
    canonicalMeta.name = 'canonical-domain';
    canonicalMeta.content = 'lvh.me';
    document.head.appendChild(canonicalMeta);

    // Mock console methods to avoid noise in tests
    jest.spyOn(console, 'log').mockImplementation(() => {});
    jest.spyOn(console, 'group').mockImplementation(() => {});
    jest.spyOn(console, 'groupEnd').mockImplementation(() => {});
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  describe('Domain Detection', () => {
    describe('isOnTenantSubdomain', () => {
      it('returns true for tenant subdomain on lvh.me', () => {
        mockLocation('http://acme-corp.lvh.me:3000/dashboard');
        expect(TurboTenantHelpers.isOnTenantSubdomain()).toBe(true);
      });

      it('returns true for tenant subdomain on bizblasts.com', () => {
        // Setup production meta tags
        const platformMeta = document.querySelector('meta[name="platform-domain"]');
        platformMeta.content = 'bizblasts.com';
        const canonicalMeta = document.querySelector('meta[name="canonical-domain"]');
        canonicalMeta.content = 'www.bizblasts.com';

        mockLocation('https://acme-corp.bizblasts.com/dashboard');
        expect(TurboTenantHelpers.isOnTenantSubdomain()).toBe(true);
      });

      it('returns false for main domain lvh.me', () => {
        mockLocation('http://lvh.me:3000/');
        expect(TurboTenantHelpers.isOnTenantSubdomain()).toBe(false);
      });

      it('returns false for www subdomain', () => {
        // Setup production meta tags
        const platformMeta = document.querySelector('meta[name="platform-domain"]');
        platformMeta.content = 'bizblasts.com';
        const canonicalMeta = document.querySelector('meta[name="canonical-domain"]');
        canonicalMeta.content = 'www.bizblasts.com';

        mockLocation('https://www.bizblasts.com/');
        expect(TurboTenantHelpers.isOnTenantSubdomain()).toBe(false);
      });

      it('returns false for non-matching domains', () => {
        mockLocation('https://example.com/');
        expect(TurboTenantHelpers.isOnTenantSubdomain()).toBe(false);
      });
    });

    describe('getCurrentTenant', () => {
      it('returns tenant name for valid subdomain', () => {
        mockLocation('http://acme-corp.lvh.me:3000/dashboard');
        expect(TurboTenantHelpers.getCurrentTenant()).toBe('acme-corp');
      });

      it('returns null for main domain', () => {
        mockLocation('http://lvh.me:3000/');
        expect(TurboTenantHelpers.getCurrentTenant()).toBe(null);
      });

      it('returns null for www subdomain', () => {
        mockLocation('https://www.bizblasts.com/');
        expect(TurboTenantHelpers.getCurrentTenant()).toBe(null);
      });
    });

    describe('isBusinessManagerArea', () => {
      it('returns true for /manage/ routes', () => {
        mockLocation('http://acme-corp.lvh.me:3000/manage/dashboard');
        expect(TurboTenantHelpers.isBusinessManagerArea()).toBe(true);
      });

      it('returns true for nested /manage/ routes', () => {
        mockLocation('http://acme-corp.lvh.me:3000/manage/bookings/new');
        expect(TurboTenantHelpers.isBusinessManagerArea()).toBe(true);
      });

      it('returns false for public routes', () => {
        mockLocation('http://acme-corp.lvh.me:3000/book-now');
        expect(TurboTenantHelpers.isBusinessManagerArea()).toBe(false);
      });

      it('returns false for root path', () => {
        mockLocation('http://acme-corp.lvh.me:3000/');
        expect(TurboTenantHelpers.isBusinessManagerArea()).toBe(false);
      });
    });
  });

  describe('Navigation Detection', () => {
    describe('isCrossTenantNavigation', () => {
      beforeEach(() => {
        mockLocation('http://acme-corp.lvh.me:3000/dashboard');
      });

      it('returns true for different subdomain', () => {
        const result = TurboTenantHelpers.isCrossTenantNavigation('http://other-corp.lvh.me:3000/dashboard');
        expect(result).toBe(true);
      });

      it('returns true for main domain from subdomain', () => {
        const result = TurboTenantHelpers.isCrossTenantNavigation('http://lvh.me:3000/pricing');
        expect(result).toBe(true);
      });

      it('returns false for same subdomain', () => {
        const result = TurboTenantHelpers.isCrossTenantNavigation('http://acme-corp.lvh.me:3000/settings');
        expect(result).toBe(false);
      });

      it('returns false for relative URLs', () => {
        const result = TurboTenantHelpers.isCrossTenantNavigation('/settings');
        expect(result).toBe(false);
      });
    });
  });

  describe('URL Generation', () => {
    beforeEach(() => {
      mockLocation('http://lvh.me:3000/');
    });

    describe('getMainDomainUrl', () => {
      it('generates correct URL for lvh.me environment', () => {
        const url = TurboTenantHelpers.getMainDomainUrl('/pricing');
        expect(url).toBe('http://lvh.me:3000/pricing');
      });

      it('generates correct URL with default path', () => {
        const url = TurboTenantHelpers.getMainDomainUrl();
        expect(url).toBe('http://lvh.me:3000/');
      });
    });

    describe('getTenantUrl', () => {
      it('generates correct tenant URL for lvh.me environment', () => {
        const url = TurboTenantHelpers.getTenantUrl('acme-corp', '/dashboard');
        expect(url).toBe('http://acme-corp.lvh.me:3000/dashboard');
      });

      it('generates correct tenant URL with default path', () => {
        const url = TurboTenantHelpers.getTenantUrl('acme-corp');
        expect(url).toBe('http://acme-corp.lvh.me:3000/');
      });
    });
  });

  describe('Form Enhancement', () => {
    describe('addTenantContextToForm', () => {
      let form;

      beforeEach(() => {
        form = document.createElement('form');
        form.action = '/test';
        document.body.appendChild(form);
      });

      it('adds tenant context for business manager area', () => {
        mockLocation('http://acme-corp.lvh.me:3000/manage/dashboard');
        
        TurboTenantHelpers.addTenantContextToForm(form);
        
        const tenantInput = form.querySelector('input[name="tenant_context"]');
        const currentTenantInput = form.querySelector('input[name="current_tenant"]');
        
        expect(tenantInput).toBeTruthy();
        expect(tenantInput.value).toBe('business-manager');
        expect(currentTenantInput).toBeTruthy();
        expect(currentTenantInput.value).toBe('acme-corp');
      });

      it('adds public context for non-business manager area', () => {
        mockLocation('http://acme-corp.lvh.me:3000/book-now');
        
        TurboTenantHelpers.addTenantContextToForm(form);
        
        const tenantInput = form.querySelector('input[name="tenant_context"]');
        expect(tenantInput).toBeTruthy();
        expect(tenantInput.value).toBe('public');
      });

      it('does not add duplicate inputs', () => {
        mockLocation('http://acme-corp.lvh.me:3000/manage/dashboard');
        
        // Add context twice
        TurboTenantHelpers.addTenantContextToForm(form);
        TurboTenantHelpers.addTenantContextToForm(form);
        
        const tenantInputs = form.querySelectorAll('input[name="tenant_context"]');
        expect(tenantInputs.length).toBe(1);
      });

      it('does not add current tenant for main domain', () => {
        mockLocation('http://lvh.me:3000/contact');
        
        TurboTenantHelpers.addTenantContextToForm(form);
        
        const currentTenantInput = form.querySelector('input[name="current_tenant"]');
        expect(currentTenantInput).toBeFalsy();
      });
    });
  });

  describe('Tenant-Sensitive Data Management', () => {
    describe('clearTenantSensitiveData', () => {
      beforeEach(() => {
        // Create test elements
        const sensitiveDiv1 = document.createElement('div');
        sensitiveDiv1.setAttribute('data-tenant-sensitive', '');
        sensitiveDiv1.id = 'sensitive-1';
        sensitiveDiv1.textContent = 'Sensitive data 1';
        
        const sensitiveDiv2 = document.createElement('div');
        sensitiveDiv2.setAttribute('data-tenant-sensitive', '');
        sensitiveDiv2.id = 'sensitive-2';
        sensitiveDiv2.textContent = 'Sensitive data 2';
        
        const normalDiv = document.createElement('div');
        normalDiv.id = 'normal';
        normalDiv.textContent = 'Normal data';
        
        document.body.appendChild(sensitiveDiv1);
        document.body.appendChild(sensitiveDiv2);
        document.body.appendChild(normalDiv);
      });

      it('hides all tenant-sensitive elements', () => {
        TurboTenantHelpers.clearTenantSensitiveData();
        
        const sensitive1 = document.getElementById('sensitive-1');
        const sensitive2 = document.getElementById('sensitive-2');
        const normal = document.getElementById('normal');
        
        expect(sensitive1.style.display).toBe('none');
        expect(sensitive2.style.display).toBe('none');
        expect(normal.style.display).toBe('');
      });

      it('returns data for restoration', () => {
        const sensitiveData = TurboTenantHelpers.clearTenantSensitiveData();
        
        expect(sensitiveData).toHaveLength(2);
        expect(sensitiveData[0].element.id).toBe('sensitive-1');
        expect(sensitiveData[1].element.id).toBe('sensitive-2');
      });
    });

    describe('restoreTenantSensitiveData', () => {
      beforeEach(() => {
        const sensitiveDiv = document.createElement('div');
        sensitiveDiv.setAttribute('data-tenant-sensitive', '');
        sensitiveDiv.id = 'sensitive-test';
        sensitiveDiv.style.display = 'none';
        document.body.appendChild(sensitiveDiv);
      });

      it('restores visibility of tenant-sensitive elements', () => {
        TurboTenantHelpers.restoreTenantSensitiveData();
        
        const sensitive = document.getElementById('sensitive-test');
        expect(sensitive.style.display).toBe('');
      });

      it('restores from provided data', () => {
        const sensitiveDiv = document.getElementById('sensitive-test');
        const sensitiveData = [{
          element: sensitiveDiv,
          originalDisplay: 'block',
          originalVisibility: 'visible'
        }];
        
        TurboTenantHelpers.restoreTenantSensitiveData(sensitiveData);
        
        expect(sensitiveDiv.style.display).toBe('block');
        expect(sensitiveDiv.style.visibility).toBe('visible');
      });
    });

    describe('shouldCacheElement', () => {
      it('returns false for tenant-sensitive elements', () => {
        const sensitiveDiv = document.createElement('div');
        sensitiveDiv.setAttribute('data-tenant-sensitive', '');
        
        expect(TurboTenantHelpers.shouldCacheElement(sensitiveDiv)).toBe(false);
      });

      it('returns false for elements inside tenant-sensitive containers', () => {
        const sensitiveContainer = document.createElement('div');
        sensitiveContainer.setAttribute('data-tenant-sensitive', '');
        
        const childElement = document.createElement('span');
        sensitiveContainer.appendChild(childElement);
        document.body.appendChild(sensitiveContainer);
        
        expect(TurboTenantHelpers.shouldCacheElement(childElement)).toBe(false);
      });

      it('returns true for normal elements', () => {
        const normalDiv = document.createElement('div');
        
        expect(TurboTenantHelpers.shouldCacheElement(normalDiv)).toBe(true);
      });
    });
  });

  describe('Debug Functionality', () => {
    describe('debugTenantInfo', () => {
      beforeEach(() => {
        // Mock process.env for testing
        process.env.NODE_ENV = 'development';
      });

      it('logs tenant information in development', () => {
        mockLocation('http://acme-corp.lvh.me:3000/manage/dashboard');
        
        TurboTenantHelpers.debugTenantInfo();
        
        expect(console.group).toHaveBeenCalledWith('🏢 Tenant Debug Info');
        expect(console.log).toHaveBeenCalledWith('Current Host:', 'acme-corp.lvh.me:3000');
        expect(console.log).toHaveBeenCalledWith('Is Tenant Subdomain:', true);
        expect(console.log).toHaveBeenCalledWith('Current Tenant:', 'acme-corp');
        expect(console.log).toHaveBeenCalledWith('Is Business Manager:', true);
        expect(console.groupEnd).toHaveBeenCalled();
      });

      it('does not log in production', () => {
        // Temporarily store original process.env
        const originalNodeEnv = process.env.NODE_ENV;

        // Set production environment
        process.env.NODE_ENV = 'production';

        // Mock a production-like hostname (not lvh.me or localhost)
        mockLocation('https://acme-corp.bizblasts.com/dashboard');

        TurboTenantHelpers.debugTenantInfo();

        expect(console.group).not.toHaveBeenCalled();

        // Restore original environment
        process.env.NODE_ENV = originalNodeEnv;
      });

      it('recognizes localhost as development environment', () => {
        // Even in production NODE_ENV, localhost should enable debug
        const originalNodeEnv = process.env.NODE_ENV;
        process.env.NODE_ENV = 'production';

        mockLocation('http://localhost:3000/dashboard');

        TurboTenantHelpers.debugTenantInfo();

        expect(console.group).toHaveBeenCalledWith('🏢 Tenant Debug Info');

        // Restore original environment
        process.env.NODE_ENV = originalNodeEnv;
      });

      it('recognizes 127.0.0.1 as development environment', () => {
        // Even in production NODE_ENV, 127.0.0.1 should enable debug
        const originalNodeEnv = process.env.NODE_ENV;
        process.env.NODE_ENV = 'production';

        mockLocation('http://127.0.0.1:3000/dashboard');

        TurboTenantHelpers.debugTenantInfo();

        expect(console.group).toHaveBeenCalledWith('🏢 Tenant Debug Info');

        // Restore original environment
        process.env.NODE_ENV = originalNodeEnv;
      });

      it('recognizes lvh.me domains as development environment', () => {
        // Even in production NODE_ENV, lvh.me should enable debug
        const originalNodeEnv = process.env.NODE_ENV;
        process.env.NODE_ENV = 'production';

        mockLocation('http://test.lvh.me:3000/dashboard');

        TurboTenantHelpers.debugTenantInfo();

        expect(console.group).toHaveBeenCalledWith('🏢 Tenant Debug Info');

        // Restore original environment
        process.env.NODE_ENV = originalNodeEnv;
      });
    });
  });

  describe('Navigation Helpers', () => {
    beforeEach(() => {
      // Mock window.location.href setter
      delete window.location;
      window.location = { href: '' };
    });

    describe('navigateToMainDomain', () => {
      it('navigates to main domain with path', () => {
        mockLocation('http://acme-corp.lvh.me:3000/dashboard');
        
        TurboTenantHelpers.navigateToMainDomain('/pricing');
        
        expect(window.location.href).toBe('http://lvh.me:3000/pricing');
      });
    });

    describe('navigateToTenant', () => {
      it('navigates to tenant with path', () => {
        mockLocation('http://lvh.me:3000/');
        
        TurboTenantHelpers.navigateToTenant('acme-corp', '/dashboard');
        
        expect(window.location.href).toBe('http://acme-corp.lvh.me:3000/dashboard');
      });
    });
  });

  describe('Canonical Domain Support', () => {
    beforeEach(() => {
      // Clear existing meta tags
      document.querySelectorAll('meta').forEach(meta => meta.remove());
    });

    it('getCanonicalDomain returns canonical domain in production', () => {
      // Setup production meta tags
      const platformMeta = document.createElement('meta');
      platformMeta.name = 'platform-domain';
      platformMeta.content = 'bizblasts.com';
      document.head.appendChild(platformMeta);

      const canonicalMeta = document.createElement('meta');
      canonicalMeta.name = 'canonical-domain';
      canonicalMeta.content = 'www.bizblasts.com';
      document.head.appendChild(canonicalMeta);

      expect(TurboTenantHelpers.getPlatformDomain()).toBe('bizblasts.com');
      expect(TurboTenantHelpers.getCanonicalDomain()).toBe('www.bizblasts.com');
    });

    it('getCanonicalDomain returns platform domain in dev/test', () => {
      // Setup dev meta tags
      const platformMeta = document.createElement('meta');
      platformMeta.name = 'platform-domain';
      platformMeta.content = 'lvh.me';
      document.head.appendChild(platformMeta);

      const canonicalMeta = document.createElement('meta');
      canonicalMeta.name = 'canonical-domain';
      canonicalMeta.content = 'lvh.me';
      document.head.appendChild(canonicalMeta);

      expect(TurboTenantHelpers.getPlatformDomain()).toBe('lvh.me');
      expect(TurboTenantHelpers.getCanonicalDomain()).toBe('lvh.me');
    });

    it('isValidPlatformDomain accepts both platform and canonical domains', () => {
      // Setup production meta tags
      const platformMeta = document.createElement('meta');
      platformMeta.name = 'platform-domain';
      platformMeta.content = 'bizblasts.com';
      document.head.appendChild(platformMeta);

      const canonicalMeta = document.createElement('meta');
      canonicalMeta.name = 'canonical-domain';
      canonicalMeta.content = 'www.bizblasts.com';
      document.head.appendChild(canonicalMeta);

      // Both should be valid
      expect(TurboTenantHelpers.isValidPlatformDomain('bizblasts.com')).toBe(true);
      expect(TurboTenantHelpers.isValidPlatformDomain('www.bizblasts.com')).toBe(true);

      // Subdomains should still work
      expect(TurboTenantHelpers.isValidPlatformDomain('salon.bizblasts.com')).toBe(true);

      // Invalid domains rejected
      expect(TurboTenantHelpers.isValidPlatformDomain('bizblasts.com.evil.com')).toBe(false);
      expect(TurboTenantHelpers.isValidPlatformDomain('mybizblasts.com')).toBe(false);
    });

    it('getMainDomainUrl uses canonical domain', () => {
      // Setup production meta tags
      const platformMeta = document.createElement('meta');
      platformMeta.name = 'platform-domain';
      platformMeta.content = 'bizblasts.com';
      document.head.appendChild(platformMeta);

      const canonicalMeta = document.createElement('meta');
      canonicalMeta.name = 'canonical-domain';
      canonicalMeta.content = 'www.bizblasts.com';
      document.head.appendChild(canonicalMeta);

      mockLocation('https://salon.bizblasts.com/dashboard');

      const mainUrl = TurboTenantHelpers.getMainDomainUrl('/pricing');
      expect(mainUrl).toBe('https://www.bizblasts.com/pricing');
    });
  });
});

// Test setup for different environments
describe('TurboTenantHelpers - Environment Specific', () => {
  beforeEach(() => {
    // Clear existing meta tags
    document.querySelectorAll('meta').forEach(meta => meta.remove());
  });

  describe('Production Environment (bizblasts.com)', () => {
    it('handles production URLs correctly', () => {
      // Setup production meta tags
      const platformMeta = document.createElement('meta');
      platformMeta.name = 'platform-domain';
      platformMeta.content = 'bizblasts.com';
      document.head.appendChild(platformMeta);

      const canonicalMeta = document.createElement('meta');
      canonicalMeta.name = 'canonical-domain';
      canonicalMeta.content = 'www.bizblasts.com';
      document.head.appendChild(canonicalMeta);

      mockLocation('https://acme-corp.bizblasts.com/dashboard');

      expect(TurboTenantHelpers.isOnTenantSubdomain()).toBe(true);
      expect(TurboTenantHelpers.getCurrentTenant()).toBe('acme-corp');

      const mainUrl = TurboTenantHelpers.getMainDomainUrl('/contact');
      expect(mainUrl).toBe('https://www.bizblasts.com/contact');

      const tenantUrl = TurboTenantHelpers.getTenantUrl('other-corp', '/settings');
      expect(tenantUrl).toBe('https://other-corp.bizblasts.com/settings');
    });
  });

  describe('Development Environment (lvh.me)', () => {
    it('handles development URLs correctly', () => {
      // Setup development meta tags
      const platformMeta = document.createElement('meta');
      platformMeta.name = 'platform-domain';
      platformMeta.content = 'lvh.me';
      document.head.appendChild(platformMeta);

      const canonicalMeta = document.createElement('meta');
      canonicalMeta.name = 'canonical-domain';
      canonicalMeta.content = 'lvh.me';
      document.head.appendChild(canonicalMeta);

      mockLocation('http://test-business.lvh.me:3000/manage/bookings');

      expect(TurboTenantHelpers.isOnTenantSubdomain()).toBe(true);
      expect(TurboTenantHelpers.getCurrentTenant()).toBe('test-business');
      expect(TurboTenantHelpers.isBusinessManagerArea()).toBe(true);

      const mainUrl = TurboTenantHelpers.getMainDomainUrl('/features');
      expect(mainUrl).toBe('http://lvh.me:3000/features');
    });
  });

  describe('Fallback Environment', () => {
    it('handles unknown domains gracefully', () => {
      mockLocation('http://unknown.example.com/test');

      expect(TurboTenantHelpers.isOnTenantSubdomain()).toBe(false);
      expect(TurboTenantHelpers.getCurrentTenant()).toBe(null);

      const mainUrl = TurboTenantHelpers.getMainDomainUrl('/test');
      // Should fall back to bizblasts.com without meta tags
      expect(mainUrl).toContain('/test');
    });
  });
}); 