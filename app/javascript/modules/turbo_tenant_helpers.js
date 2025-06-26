// Tenant-aware Turbo utility functions
// Provides helpers for managing Turbo navigation in a multi-tenant environment

export class TurboTenantHelpers {
  // Check if current page is in business manager area
  static isBusinessManagerArea() {
    return window.location.pathname.startsWith('/manage/');
  }
  
  // Check if current page is on a tenant subdomain
  static isOnTenantSubdomain() {
    const host = window.location.host;
    const parts = host.split('.');
    
    // In development: something.lvh.me
    // In production: something.bizblasts.com
    if (host.includes('lvh.me')) {
      return parts.length >= 3 && parts[0] !== 'www';
    }
    
    if (host.includes('bizblasts.com')) {
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
    
    if (window.location.host.includes('lvh.me')) {
      return `${protocol}//lvh.me${portSuffix}${path}`;
    }
    
    if (window.location.host.includes('bizblasts.com')) {
      return `${protocol}//www.bizblasts.com${path}`;
    }
    
    // Fallback for other environments
    return `${protocol}//${window.location.host}${path}`;
  }
  
  // Get tenant-specific URL
  static getTenantUrl(tenantSlug, path = '/') {
    const protocol = window.location.protocol;
    const port = window.location.port;
    const portSuffix = port && !['80', '443'].includes(port) ? `:${port}` : '';
    
    if (window.location.host.includes('lvh.me')) {
      return `${protocol}//${tenantSlug}.lvh.me${portSuffix}${path}`;
    }
    
    if (window.location.host.includes('bizblasts.com')) {
      return `${protocol}//${tenantSlug}.bizblasts.com${path}`;
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
    const isDev = (typeof process !== 'undefined' && process.env && process.env.NODE_ENV === 'development') ||
                  (typeof window !== 'undefined' && window.location && 
                   (window.location.hostname.includes('lvh.me') || window.location.hostname === 'localhost'));
    
    if (isDev) {
      console.group('🏢 Tenant Debug Info');
      console.log('Current Host:', window.location.host);
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
} else if (typeof window !== 'undefined' && window.location && window.location.hostname && 
           (window.location.hostname.includes('lvh.me') || window.location.hostname === 'localhost')) {
  // Development environment detection fallback
  window.TenantHelpers = TurboTenantHelpers;
}

export default TurboTenantHelpers; 