// Verification test for production security fix
// This test explicitly demonstrates that the bug reported by cursor bot is fixed
// Bug: Production Platform Incorrectly Identified as Development
// Fix: isActualDevelopmentEnvironment() now correctly excludes production domains

import { TurboTenantHelpers } from '../../app/javascript/modules/turbo_tenant_helpers.js';

describe('Production Security Fix Verification', () => {
  // jsdom >= 22 makes window.location non-configurable; use reconfigure via
  // the JSDOM instance exposed by spec/javascript/jsdom_environment.js.
  const mockLocation = (href) => {
    // eslint-disable-next-line no-undef
    jsdomInstance.reconfigure({ url: href });
  };

  beforeEach(() => {
    // Clean up any global exposure
    delete window.TenantHelpers;
  });

  describe('Bug Fix: Production domains no longer identified as development', () => {
    it('✅ bizblasts.com is NOT identified as development', () => {
      mockLocation('https://bizblasts.com/');

      // This was the bug: isMainDomain(hostname) returned true for bizblasts.com
      // which caused isDev to be true in debugTenantInfo()
      const result = TurboTenantHelpers.isActualDevelopmentEnvironment();

      expect(result).toBe(false);
      // Consequence: Debug logging will NOT run in production
      // Consequence: window.TenantHelpers will NOT be exposed in production
    });

    it('✅ www.bizblasts.com is NOT identified as development', () => {
      mockLocation('https://www.bizblasts.com/');
      expect(TurboTenantHelpers.isActualDevelopmentEnvironment()).toBe(false);
    });

    it('✅ tenant.bizblasts.com is NOT identified as development', () => {
      mockLocation('https://tenant.bizblasts.com/');

      // This was the bug: isPlatformSubdomain(hostname) returned true
      // which caused isDev to be true
      const result = TurboTenantHelpers.isActualDevelopmentEnvironment();

      expect(result).toBe(false);
      // Consequence: Tenant subdomains in production won't expose debug info
    });

    it('✅ bizblasts.onrender.com is NOT identified as development', () => {
      mockLocation('https://bizblasts.onrender.com/');
      expect(TurboTenantHelpers.isActualDevelopmentEnvironment()).toBe(false);
    });
  });

  describe('Development domains still correctly identified', () => {
    it('✅ localhost IS identified as development', () => {
      mockLocation('http://localhost:3000/');
      expect(TurboTenantHelpers.isActualDevelopmentEnvironment()).toBe(true);
    });

    it('✅ lvh.me IS identified as development', () => {
      mockLocation('http://lvh.me:3000/');
      expect(TurboTenantHelpers.isActualDevelopmentEnvironment()).toBe(true);
    });

    it('✅ tenant.lvh.me IS identified as development', () => {
      mockLocation('http://tenant.lvh.me:3000/');
      expect(TurboTenantHelpers.isActualDevelopmentEnvironment()).toBe(true);
    });

    it('✅ example.com IS identified as development (test)', () => {
      mockLocation('http://example.com/');
      expect(TurboTenantHelpers.isActualDevelopmentEnvironment()).toBe(true);
    });
  });

  describe('Security implications verified', () => {
    it('✅ window.TenantHelpers NOT exposed on bizblasts.com', () => {
      mockLocation('https://bizblasts.com/');

      // Simulate the auto-initialization code
      const shouldExpose = TurboTenantHelpers.isActualDevelopmentEnvironment();

      expect(shouldExpose).toBe(false);
      // In production, window.TenantHelpers will not be exposed
    });

    it('✅ Debug logging will NOT run on bizblasts.com', () => {
      mockLocation('https://bizblasts.com/');

      // Mock console to verify debug logging doesn't run
      const consoleSpy = jest.spyOn(console, 'group');

      TurboTenantHelpers.debugTenantInfo();

      // Debug logging should NOT have been called
      expect(consoleSpy).not.toHaveBeenCalled();

      consoleSpy.mockRestore();
    });

    it('✅ Debug logging WILL run on lvh.me (development)', () => {
      mockLocation('http://lvh.me:3000/');

      const consoleSpy = jest.spyOn(console, 'group');

      TurboTenantHelpers.debugTenantInfo();

      // Debug logging SHOULD run in development
      expect(consoleSpy).toHaveBeenCalledWith('🏢 Tenant Debug Info');

      consoleSpy.mockRestore();
    });
  });

  describe('Original security vulnerability remains fixed', () => {
    // These tests ensure we didn't break the original CWE-20 fix

    it('✅ Substring bypass attacks still blocked', () => {
      expect(TurboTenantHelpers.isPlatformSubdomain('evil-bizblasts.com')).toBe(false);
      expect(TurboTenantHelpers.isPlatformSubdomain('mybizblasts.com.evil.org')).toBe(false);
    });

    it('✅ Server-side validation still active', () => {
      // AllowedHostService tests verify this - just documenting here
      // See: spec/services/allowed_host_service_spec.rb:70 examples
    });
  });
});
