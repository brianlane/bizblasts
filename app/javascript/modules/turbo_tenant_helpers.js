// Tenant-aware Turbo utility functions
// Provides helpers for managing Turbo navigation in a multi-tenant environment

export class TurboTenantHelpers {
  // Get server-provided platform domain (base domain for subdomain validation)
  // Returns: "bizblasts.com" (production) or "lvh.me" (dev/test)
  static getPlatformDomain() {
    const metaTag = document.querySelector('meta[name="platform-domain"]');
    return metaTag?.content || 'bizblasts.com'; // Fallback for non-Rails contexts
  }

  // Get server-provided canonical domain (preferred domain for main site URLs)
  // Returns: "www.bizblasts.com" (production) or "lvh.me" (dev/test)
  static getCanonicalDomain() {
    const metaTag = document.querySelector('meta[name="canonical-domain"]');
    // Fallback to platform domain if canonical not set
    return metaTag?.content || this.getPlatformDomain();
  }

  // Get current tenant type from server
  static getTenantType() {
    const metaTag = document.querySelector('meta[name="tenant-type"]');
    return metaTag?.content || 'platform';
  }

  // Check if current context is a custom domain
  static isCustomDomain() {
    const metaTag = document.querySelector('meta[name="is-custom-domain"]');
    return metaTag?.content === 'true';
  }

  // SECURITY: Validate hostname against platform domain (prevents domain spoofing)
  // Only accepts exact match or valid subdomain (e.g., "tenant.bizblasts.com")
  // Also accepts canonical domain (e.g., "www.bizblasts.com" in production)
  // Rejects: "bizblasts.com.evil.com", "evil-bizblasts.com", "mybizblasts.com"
  static isValidPlatformDomain(hostname) {
    if (!hostname) return false;

    const platformDomain = this.getPlatformDomain();
    const canonicalDomain = this.getCanonicalDomain();
    const normalizedHost = hostname.toLowerCase();
    const normalizedPlatform = platformDomain.toLowerCase();
    const normalizedCanonical = canonicalDomain.toLowerCase();

    // Exact match with platform domain (e.g., "bizblasts.com" === "bizblasts.com")
    if (normalizedHost === normalizedPlatform) {
      return true;
    }

    // Exact match with canonical domain (e.g., "www.bizblasts.com" === "www.bizblasts.com")
    if (normalizedHost === normalizedCanonical) {
      return true;
    }

    // Valid subdomain (ends with ".bizblasts.com")
    // This prevents "bizblasts.com.evil.com" and "evil-bizblasts.com"
    if (normalizedHost.endsWith(`.${normalizedPlatform}`)) {
      return true;
    }

    return false;
  }

  // Check if current page is in business manager area
  static isBusinessManagerArea() {
    return window.location.pathname.startsWith('/manage/');
  }
  
  // Check if current page is on a tenant subdomain
  static isOnTenantSubdomain() {
    // Use hostname (without port) instead of host for proper domain checking
    const hostname = window.location.hostname;
    const parts = hostname.split('.');

    // Check if we're on a valid platform domain
    if (!this.isValidPlatformDomain(hostname)) {
      return false;
    }

    // Must have at least 3 parts (subdomain.platform.tld) and not be www
    return parts.length >= 3 && parts[0] !== 'www';
  }
  
  // Get current tenant subdomain
  static getCurrentTenant() {
    if (!this.isOnTenantSubdomain()) return null;
    
    const host = window.location.host;
    const parts = host.split('.');
    return parts[0];
  }
  
  // Check if URL is cross-tenant navigation
  static isCrossTenantNavigation(targetUrl) {
    try {
      const currentHost = window.location.host;
      
      // Handle relative URLs - they are not cross-tenant
      if (!targetUrl.startsWith('http://') && !targetUrl.startsWith('https://')) {
        return false;
      }
      
      const targetHost = new URL(targetUrl).host;
      return currentHost !== targetHost;
    } catch (error) {
      // If URL parsing fails, assume it's not cross-tenant
      return false;
    }
  }
  
  // Get main domain URL for current environment
  // Uses canonical domain (www.bizblasts.com in production, lvh.me in dev/test)
  static getMainDomainUrl(path = '/') {
    const protocol = window.location.protocol;
    const port = window.location.port;
    const portSuffix = port && !['80', '443'].includes(port) ? `:${port}` : '';

    const canonicalDomain = this.getCanonicalDomain();
    return `${protocol}//${canonicalDomain}${portSuffix}${path}`;
  }
  
  // Get tenant-specific URL
  // IMPORTANT: Only works for subdomain tenants on platform domain
  // Custom domain businesses cannot be accessed via this method
  static getTenantUrl(tenantSlug, path = '/') {
    const protocol = window.location.protocol;
    const port = window.location.port;
    const portSuffix = port && !['80', '443'].includes(port) ? `:${port}` : '';

    const tenantType = this.getTenantType();
    const platformDomain = this.getPlatformDomain();

    // Only construct subdomain URLs when on platform domain or subdomain tenant
    if (tenantType === 'subdomain' || tenantType === 'platform') {
      return `${protocol}//${tenantSlug}.${platformDomain}${portSuffix}${path}`;
    }

    // Custom domain businesses - cannot construct cross-tenant URLs
    console.warn('[TenantHelpers] getTenantUrl called from custom domain context - returning relative path');
    return path; // Return relative path as fallback
  }
  
  // Navigate to main domain (useful for logout, etc.)
  static navigateToMainDomain(path = '/') {
    const url = this.getMainDomainUrl(path);
    window.location.href = url;
  }
  
  // Navigate to specific tenant
  static navigateToTenant(tenantSlug, path = '/') {
    const url = this.getTenantUrl(tenantSlug, path);
    window.location.href = url;
  }
  
  // Add tenant context to form data
  static addTenantContextToForm(form) {
    const tenantContext = this.isBusinessManagerArea() ? 'business-manager' : 'public';
    const currentTenant = this.getCurrentTenant();
    
    // Add tenant context
    if (!form.querySelector('input[name="tenant_context"]')) {
      const tenantInput = document.createElement('input');
      tenantInput.type = 'hidden';
      tenantInput.name = 'tenant_context';
      tenantInput.value = tenantContext;
      form.appendChild(tenantInput);
    }
    
    // Add current tenant if on subdomain
    if (currentTenant && !form.querySelector('input[name="current_tenant"]')) {
      const currentTenantInput = document.createElement('input');
      currentTenantInput.type = 'hidden';
      currentTenantInput.name = 'current_tenant';
      currentTenantInput.value = currentTenant;
      form.appendChild(currentTenantInput);
    }
  }
  
  // Check if element should be cached (tenant-sensitive elements should not be)
  static shouldCacheElement(element) {
    return !element.hasAttribute('data-tenant-sensitive') &&
           !element.closest('[data-tenant-sensitive]');
  }
  
  // Clear tenant-sensitive data before caching
  static clearTenantSensitiveData() {
    const sensitiveElements = document.querySelectorAll('[data-tenant-sensitive]');
    const sensitiveData = [];
    
    sensitiveElements.forEach((element, index) => {
      // Store original state for restoration
      sensitiveData.push({
        element,
        originalDisplay: element.style.display,
        originalVisibility: element.style.visibility
      });
      
      // Hide element
      element.style.display = 'none';
    });
    
    return sensitiveData; // Return for potential restoration
  }
  
  // Restore tenant-sensitive data after navigation
  static restoreTenantSensitiveData(sensitiveData = null) {
    if (sensitiveData) {
      // Restore from provided data
      sensitiveData.forEach(({ element, originalDisplay, originalVisibility }) => {
        element.style.display = originalDisplay;
        element.style.visibility = originalVisibility;
      });
    } else {
      // Simple restoration - just show all sensitive elements
      const sensitiveElements = document.querySelectorAll('[data-tenant-sensitive]');
      sensitiveElements.forEach(element => {
        element.style.display = '';
        element.style.visibility = '';
      });
    }
  }
  
  // Debug helper - log tenant information
  static debugTenantInfo() {
    const platformDomain = this.getPlatformDomain();
    const canonicalDomain = this.getCanonicalDomain();

    // SECURITY: Only enable debug logging in actual development environments
    // Check for development-specific domains (localhost, 127.0.0.1, lvh.me)
    // This prevents debug logging from being enabled in production
    const isDev = (typeof process !== 'undefined' && process.env && process.env.NODE_ENV === 'development') ||
                  (typeof window !== 'undefined' && window.location &&
                   (window.location.hostname === 'localhost' ||
                    window.location.hostname === '127.0.0.1' ||
                    window.location.hostname.includes('lvh.me')));

    if (isDev) {
      console.group('🏢 Tenant Debug Info');
      console.log('Platform Domain (base):', platformDomain);
      console.log('Canonical Domain (www):', canonicalDomain);
      console.log('Current Host:', window.location.host);
      console.log('Is Valid Platform Domain:', this.isValidPlatformDomain(window.location.hostname));
      console.log('Is Tenant Subdomain:', this.isOnTenantSubdomain());
      console.log('Current Tenant:', this.getCurrentTenant());
      console.log('Tenant Type:', this.getTenantType());
      console.log('Is Custom Domain:', this.isCustomDomain());
      console.log('Is Business Manager:', this.isBusinessManagerArea());
      console.log('Main Domain URL:', this.getMainDomainUrl());
      console.groupEnd();
    }
  }
}

// Auto-initialize debugging in development
if (typeof process !== 'undefined' && process.env && process.env.NODE_ENV === 'development') {
  // Add global helper for debugging
  window.TenantHelpers = TurboTenantHelpers;

  // Log tenant info on page load
  document.addEventListener('DOMContentLoaded', () => {
    TurboTenantHelpers.debugTenantInfo();
  });
} else if (typeof window !== 'undefined' && window.location && window.location.hostname) {
  // Make helpers available in all environments for debugging
  window.TenantHelpers = TurboTenantHelpers;
}

export default TurboTenantHelpers; 