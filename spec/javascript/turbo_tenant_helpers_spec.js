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

    // Mock console methods to avoid noise in tests
    jest.spyOn(console, 'log').mockImplementation(() => {});
    jest.spyOn(console, 'group').mockImplementation(() => {});
    jest.spyOn(console, 'groupEnd').mockImplementation(() => {});
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  describe('Security - Domain Validation', () => {
    describe('getPrimaryDomain', () => {
      it('returns example.com for test environment', () => {
        mockLocation('http://example.com/');
        expect(TurboTenantHelpers.getPrimaryDomain()).toBe('example.com');
      });

      it('returns lvh.me for development environment', () => {
        mockLocation('http://lvh.me:3000/');
        expect(TurboTenantHelpers.getPrimaryDomain()).toBe('lvh.me');
      });

      it('returns lvh.me for localhost', () => {
        mockLocation('http://localhost:3000/');
        expect(TurboTenantHelpers.getPrimaryDomain()).toBe('lvh.me');
      });

      it('defaults to bizblasts.com for production', () => {
        mockLocation('https://bizblasts.com/');
        expect(TurboTenantHelpers.getPrimaryDomain()).toBe('bizblasts.com');
      });
    });

    describe('isMainDomain', () => {
      it('returns true for exact main domain match', () => {
        mockLocation('http://example.com/');
        expect(TurboTenantHelpers.isMainDomain('example.com')).toBe(true);
      });

      it('returns true for www variant', () => {
        mockLocation('http://example.com/');
        expect(TurboTenantHelpers.isMainDomain('www.example.com')).toBe(true);
      });

      it('returns true for localhost', () => {
        mockLocation('http://localhost:3000/');
        expect(TurboTenantHelpers.isMainDomain('localhost')).toBe(true);
      });

      it('returns false for tenant subdomain', () => {
        mockLocation('http://example.com/');
        expect(TurboTenantHelpers.isMainDomain('tenant.example.com')).toBe(false);
      });

      it('normalizes host with port', () => {
        mockLocation('http://example.com:3000/');
        expect(TurboTenantHelpers.isMainDomain('example.com:3000')).toBe(true);
      });

      it('normalizes case', () => {
        mockLocation('http://example.com/');
        expect(TurboTenantHelpers.isMainDomain('EXAMPLE.COM')).toBe(true);
      });

      it('returns false for null/undefined', () => {
        mockLocation('http://example.com/');
        expect(TurboTenantHelpers.isMainDomain(null)).toBe(false);
        expect(TurboTenantHelpers.isMainDomain(undefined)).toBe(false);
        expect(TurboTenantHelpers.isMainDomain('')).toBe(false);
      });
    });

    describe('isPlatformSubdomain - Security Tests', () => {
      beforeEach(() => {
        mockLocation('http://example.com/');
      });

      it('returns true for valid tenant subdomain', () => {
        expect(TurboTenantHelpers.isPlatformSubdomain('tenant.example.com')).toBe(true);
      });

      it('returns true for subdomain with hyphens', () => {
        expect(TurboTenantHelpers.isPlatformSubdomain('my-business.example.com')).toBe(true);
      });

      it('returns true for subdomain with numbers', () => {
        expect(TurboTenantHelpers.isPlatformSubdomain('tenant123.example.com')).toBe(true);
      });

      // CRITICAL SECURITY TESTS - These should all return FALSE
      it('rejects evil-example.com (bypass attempt - no dot before domain)', () => {
        expect(TurboTenantHelpers.isPlatformSubdomain('evil-example.com')).toBe(false);
      });

      it('rejects myexample.com.evil.org (bypass attempt - domain in middle)', () => {
        expect(TurboTenantHelpers.isPlatformSubdomain('myexample.com.evil.org')).toBe(false);
      });

      it('rejects example.com.evil.org (bypass attempt)', () => {
        expect(TurboTenantHelpers.isPlatformSubdomain('example.com.evil.org')).toBe(false);
      });

      it('rejects multi-level subdomains', () => {
        expect(TurboTenantHelpers.isPlatformSubdomain('sub.tenant.example.com')).toBe(false);
      });

      it('rejects main domain without subdomain', () => {
        expect(TurboTenantHelpers.isPlatformSubdomain('example.com')).toBe(false);
      });

      it('rejects www subdomain (reserved for main domain)', () => {
        expect(TurboTenantHelpers.isPlatformSubdomain('www.example.com')).toBe(false);
      });

      it('handles case normalization', () => {
        expect(TurboTenantHelpers.isPlatformSubdomain('TENANT.EXAMPLE.COM')).toBe(true);
      });

      it('handles ports correctly', () => {
        expect(TurboTenantHelpers.isPlatformSubdomain('tenant.example.com:3000')).toBe(true);
      });

      it('returns false for null/undefined/empty', () => {
        expect(TurboTenantHelpers.isPlatformSubdomain(null)).toBe(false);
        expect(TurboTenantHelpers.isPlatformSubdomain(undefined)).toBe(false);
        expect(TurboTenantHelpers.isPlatformSubdomain('')).toBe(false);
      });
    });

    describe('isPlatformSubdomain - Production Environment', () => {
      it('validates bizblasts.com subdomains correctly', () => {
        mockLocation('https://bizblasts.com/');

        expect(TurboTenantHelpers.isPlatformSubdomain('tenant.bizblasts.com')).toBe(true);
        expect(TurboTenantHelpers.isPlatformSubdomain('evil-bizblasts.com')).toBe(false);
        expect(TurboTenantHelpers.isPlatformSubdomain('mybizblasts.com.evil.org')).toBe(false);
      });
    });

    describe('isPlatformSubdomain - Development Environment', () => {
      it('validates lvh.me subdomains correctly', () => {
        mockLocation('http://lvh.me:3000/');

        expect(TurboTenantHelpers.isPlatformSubdomain('tenant.lvh.me')).toBe(true);
        expect(TurboTenantHelpers.isPlatformSubdomain('evil-lvh.me')).toBe(false);
        expect(TurboTenantHelpers.isPlatformSubdomain('mylvh.me.evil.org')).toBe(false);
      });
    });
  });

  describe('Domain Detection', () => {
    describe('isOnTenantSubdomain', () => {
      it('returns true for tenant subdomain on lvh.me', () => {
        mockLocation('http://acme-corp.lvh.me:3000/dashboard');
        expect(TurboTenantHelpers.isOnTenantSubdomain()).toBe(true);
      });

      it('returns true for tenant subdomain on bizblasts.com', () => {
        mockLocation('https://acme-corp.bizblasts.com/dashboard');
        expect(TurboTenantHelpers.isOnTenantSubdomain()).toBe(true);
      });

      it('returns false for main domain lvh.me', () => {
        mockLocation('http://lvh.me:3000/');
        expect(TurboTenantHelpers.isOnTenantSubdomain()).toBe(false);
      });

      it('returns false for www subdomain', () => {
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

      it('does not log in production on unknown domains', () => {
        // Temporarily store original process.env
        const originalNodeEnv = process.env.NODE_ENV;

        // Set production environment
        process.env.NODE_ENV = 'production';

        // Mock an unknown hostname (not platform domain)
        mockLocation('https://custom-domain.com/dashboard');

        TurboTenantHelpers.debugTenantInfo();

        expect(console.group).not.toHaveBeenCalled();

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
});

// Test setup for different environments
describe('TurboTenantHelpers - Environment Specific', () => {
  describe('Production Environment (bizblasts.com)', () => {
    it('handles production URLs correctly', () => {
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
      mockLocation('http://test-business.lvh.me:3000/manage/bookings');
      
      expect(TurboTenantHelpers.isOnTenantSubdomain()).toBe(true);
      expect(TurboTenantHelpers.getCurrentTenant()).toBe('test-business');
      expect(TurboTenantHelpers.isBusinessManagerArea()).toBe(true);
      
      const mainUrl = TurboTenantHelpers.getMainDomainUrl('/features');
      expect(mainUrl).toBe('http://lvh.me:3000/features');
    });
  });

  describe('Fallback Environment', () => {
    it('validates unknown subdomains by pattern (server validates registration)', () => {
      // unknown.example.com is a valid subdomain PATTERN - server will check if it's registered
      mockLocation('http://unknown.example.com/test');

      // Client-side validation only checks pattern, not registration
      expect(TurboTenantHelpers.isOnTenantSubdomain()).toBe(true);
      expect(TurboTenantHelpers.getCurrentTenant()).toBe('unknown');

      // Since it's a platform subdomain, main domain URL should point to example.com
      const mainUrl = TurboTenantHelpers.getMainDomainUrl('/test');
      expect(mainUrl).toBe('http://example.com/test');
    });

    it('handles truly unknown domains (not platform)', () => {
      // A domain that's not part of any platform domain
      mockLocation('http://completely-different.org/test');

      // Not a platform subdomain (doesn't end with .example.com, .lvh.me, or .bizblasts.com)
      expect(TurboTenantHelpers.isOnTenantSubdomain()).toBe(false);
      expect(TurboTenantHelpers.getCurrentTenant()).toBe(null);

      // Fallback returns current host
      const mainUrl = TurboTenantHelpers.getMainDomainUrl('/test');
      expect(mainUrl).toBe('http://completely-different.org/test');
    });
  });
}); 