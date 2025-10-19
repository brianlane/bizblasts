// Tenant-aware Turbo utility functions
// Provides helpers for managing Turbo navigation in a multi-tenant environment

export class TurboTenantHelpers {
  // Get the primary platform domain for current environment
  // This should match Rails' AllowedHostService.primary_domain
  static getPrimaryDomain() {
    // In production builds, this would be injected as 'bizblasts.com'
    // In development/test, we detect based on current host
    const host = window.location.host.toLowerCase().split(':')[0];

    // Check if we're on a known development/test domain
    // Use strict checking: exact match or single-level subdomain only
    if (host === 'lvh.me' || host === 'localhost' || host === '127.0.0.1' ||
        /^[a-z0-9-]+\.lvh\.me$/i.test(host)) {
      return 'lvh.me';
    }

    // Check if we're on a test domain
    // Use strict checking: exact match, www, or single-level subdomain
    if (host === 'example.com' || host === 'www.example.com' || host === 'test.host' ||
        /^[a-z0-9-]+\.example\.com$/i.test(host)) {
      return 'example.com';
    }

    // Check if we're on bizblasts.com domain
    if (host === 'bizblasts.com' || host === 'www.bizblasts.com' ||
        /^[a-z0-9-]+\.bizblasts\.com$/i.test(host)) {
      return 'bizblasts.com';
    }

    // Default to production domain for unknown hosts
    return 'bizblasts.com';
  }

  // Check if a host is the main platform domain (not a tenant)
  // Uses exact matching to prevent bypass attacks
  static isMainDomain(host) {
    if (!host) return false;

    // Normalize: remove port and lowercase
    const normalizedHost = host.toLowerCase().split(':')[0];
    const primaryDomain = this.getPrimaryDomain();

    // Exact match for main domains
    const mainDomains = [
      primaryDomain,
      `www.${primaryDomain}`,
      'localhost',
      '127.0.0.1',
      'test.host'
    ];

    return mainDomains.includes(normalizedHost);
  }

  // Check if a host is a valid platform subdomain
  // Uses regex structural validation to prevent bypass attacks like:
  // - evil-bizblasts.com (missing dot before domain)
  // - mybizblasts.com.evil.org (domain not at end)
  static isPlatformSubdomain(host) {
    if (!host) return false;

    // Normalize: remove port and lowercase
    const normalizedHost = host.toLowerCase().split(':')[0];
    const primaryDomain = this.getPrimaryDomain();

    // Build regex to match exactly one subdomain level
    // Pattern: ^[a-z0-9-]+\.PRIMARY_DOMAIN$
    // This ensures:
    // - Starts with subdomain name (alphanumeric + hyphens)
    // - Has exactly one dot before the primary domain
    // - Ends with the primary domain (anchored with $)
    const escapedDomain = primaryDomain.replace(/\./g, '\\.');
    const subdomainPattern = new RegExp(`^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\\.${escapedDomain}$`, 'i');

    if (subdomainPattern.test(normalizedHost)) {
      // Extract subdomain part to check if it's 'www'
      // www is a main domain indicator, not a tenant subdomain
      const subdomain = normalizedHost.split('.')[0];
      if (subdomain === 'www') {
        return false;
      }
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
    const host = window.location.host;
    const parts = host.split('.');

    // Use strict validation instead of substring matching
    if (this.isPlatformSubdomain(host)) {
      // Ensure it's not the www subdomain (which is main domain, not tenant)
      return parts.length >= 3 && parts[0] !== 'www';
    }

    return false;
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
  static getMainDomainUrl(path = '/') {
    const protocol = window.location.protocol;
    const port = window.location.port;
    const portSuffix = port && !['80', '443'].includes(port) ? `:${port}` : '';
    const primaryDomain = this.getPrimaryDomain();

    // Use strict domain validation
    const currentHost = window.location.host.toLowerCase().split(':')[0];

    // Check if we're on a platform domain (main or subdomain)
    if (this.isMainDomain(currentHost) || this.isPlatformSubdomain(currentHost)) {
      // For development/test, use plain domain
      if (primaryDomain === 'lvh.me' || primaryDomain === 'example.com') {
        return `${protocol}//${primaryDomain}${portSuffix}${path}`;
      }

      // For production, use www variant
      return `${protocol}//www.${primaryDomain}${path}`;
    }

    // Fallback for other environments (custom domains, etc.)
    return `${protocol}//${window.location.host}${path}`;
  }
  
  // Get tenant-specific URL
  static getTenantUrl(tenantSlug, path = '/') {
    const protocol = window.location.protocol;
    const port = window.location.port;
    const portSuffix = port && !['80', '443'].includes(port) ? `:${port}` : '';
    const primaryDomain = this.getPrimaryDomain();

    // Use strict domain validation
    const currentHost = window.location.host.toLowerCase().split(':')[0];

    // Check if we're on a platform domain (main or subdomain)
    if (this.isMainDomain(currentHost) || this.isPlatformSubdomain(currentHost)) {
      return `${protocol}//${tenantSlug}.${primaryDomain}${portSuffix}${path}`;
    }

    // Fallback for other environments
    return `${protocol}//${tenantSlug}.${window.location.host}${path}`;
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
    // Check for development environment more robustly
    // Use strict domain checking instead of substring matching
    const hostname = window.location.hostname.toLowerCase();
    const isDev = (typeof process !== 'undefined' && process.env && process.env.NODE_ENV === 'development') ||
                  (typeof window !== 'undefined' && window.location &&
                   (this.isMainDomain(hostname) || this.isPlatformSubdomain(hostname)));

    if (isDev) {
      console.group('🏢 Tenant Debug Info');
      console.log('Current Host:', window.location.host);
      console.log('Primary Domain:', this.getPrimaryDomain());
      console.log('Is Main Domain:', this.isMainDomain(window.location.host));
      console.log('Is Platform Subdomain:', this.isPlatformSubdomain(window.location.host));
      console.log('Is Tenant Subdomain:', this.isOnTenantSubdomain());
      console.log('Current Tenant:', this.getCurrentTenant());
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
  // Development environment detection fallback
  // Use strict validation instead of substring matching
  const hostname = window.location.hostname.toLowerCase();
  if (TurboTenantHelpers.isMainDomain(hostname) ||
      TurboTenantHelpers.isPlatformSubdomain(hostname) ||
      hostname === 'localhost' || hostname === '127.0.0.1') {
    window.TenantHelpers = TurboTenantHelpers;
  }
}

export default TurboTenantHelpers; 