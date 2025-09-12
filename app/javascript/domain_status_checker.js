// Domain Status Checker for Business Settings
// Provides real-time domain configuration status checking with throttling

class DomainStatusChecker {
  constructor() {
    this.lastCheckTime = 0;
    this.minCheckInterval = 10000; // 10 seconds minimum between checks
    this.checkInProgress = false;
    this.autoInitDone = false;
    
    this.initializeElements();
    this.bindEvents();
  }

  initializeElements() {
    this.button = document.getElementById('check-domain-btn');
    this.statusText = document.getElementById('domain-status-text');
    this.statusDetails = document.getElementById('domain-status-details');
    this.statusIndicator = document.getElementById('domain-status-indicator')?.querySelector('div');
    this.detailsExpanded = document.getElementById('domain-status-details-expanded');
    this.domainStatusContainer = document.getElementById('domain-status-container');
  }

  bindEvents() {
    if (this.button) {
      this.button.addEventListener('click', (e) => {
        e.preventDefault();
        this.checkDomainStatus();
      });
    }
  }

  async checkDomainStatus() {
    // Throttling: prevent rapid-fire clicks
    const now = Date.now();
    if (now - this.lastCheckTime < this.minCheckInterval) {
      const remainingTime = Math.ceil((this.minCheckInterval - (now - this.lastCheckTime)) / 1000);
      this.showThrottleMessage(remainingTime);
      return;
    }

    // Prevent multiple simultaneous checks
    if (this.checkInProgress) {
      return;
    }

    this.checkInProgress = true;
    this.lastCheckTime = now;
    
    try {
      this.updateUIToCheckingState();
      
      const response = await fetch(this.getCheckDomainStatusUrl(), {
        method: 'GET',
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        }
      });
      
      const data = await response.json();
      
      if (response.ok) {
        this.updateDomainStatusUI(data);
        this.showDetailedStatus(data);

        // If backend reports full success, finalize activation via POST (idempotent)
        if (data.overall_status && !data.business_status?.custom_domain_allow) {
          try {
            await fetch(this.getFinalizeActivationUrl(), {
              method: 'POST',
              headers: {
                'Accept': 'application/json',
                'X-Requested-With': 'XMLHttpRequest',
                'X-CSRF-Token': this.getCsrfToken()
              }
            });
          } catch (e) {
            // Non-blocking; UI already shows success and the background job will complete
            console.warn('Finalize activation failed (non-blocking):', e);
          }
        }
      } else {
        this.showDomainStatusError(data.error || 'Failed to check domain status');
      }
    } catch (error) {
      console.error('Domain status check failed:', error);
      this.showDomainStatusError('Network error occurred while checking domain status');
    } finally {
      this.resetButton();
      this.checkInProgress = false;
    }
  }

  showThrottleMessage(remainingSeconds) {
    if (this.statusDetails) {
      this.statusDetails.textContent = `Please wait ${remainingSeconds} more seconds before checking again`;
      this.statusDetails.className = 'text-xs text-yellow-600 mt-1';
    }
  }

  updateUIToCheckingState() {
    if (this.button) {
      this.button.disabled = true;
      this.button.innerHTML = `
        <svg class="animate-spin w-3 h-3 mr-1.5" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
        </svg>
        Checking...
      `;
    }
    
    if (this.statusText) {
      this.statusText.textContent = 'Checking status...';
    }
    
    if (this.statusDetails) {
      this.statusDetails.textContent = 'Please wait while we verify your domain configuration';
      this.statusDetails.className = 'text-xs text-gray-500 mt-1';
    }
    
    if (this.statusIndicator) {
      this.statusIndicator.className = 'w-3 h-3 bg-yellow-400 rounded-full mr-2';
    }
  }

  resetButton() {
    if (this.button) {
      this.button.disabled = false;
      this.button.innerHTML = `
        <svg class="w-3 h-3 mr-1.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
        </svg>
        Check Now
      `;
    }
  }

  updateDomainStatusUI(data) {
    if (this.statusText) {
      this.statusText.textContent = data.status_message;
    }
    
    if (this.statusIndicator) {
      if (data.overall_status) {
        this.statusIndicator.className = 'w-3 h-3 bg-green-500 rounded-full mr-2';
        if (this.statusDetails) {
          this.statusDetails.textContent = 'Your domain is fully configured and working correctly';
          this.statusDetails.className = 'text-xs text-green-600 mt-1';
        }
      } else if (data.dns_check.verified || data.render_check.verified || data.health_check.healthy) {
        this.statusIndicator.className = 'w-3 h-3 bg-yellow-500 rounded-full mr-2';
        if (this.statusDetails) {
          // Show more specific message for certificate propagation
          if (data.status_message && data.status_message.includes('certificate') && data.status_message.includes('provisioning')) {
            this.statusDetails.textContent = 'SSL certificate is propagating to all servers (usually takes 5-30 minutes)';
          } else {
            this.statusDetails.textContent = 'Domain configuration is in progress';
          }
          this.statusDetails.className = 'text-xs text-yellow-600 mt-1';
        }
      } else {
        this.statusIndicator.className = 'w-3 h-3 bg-red-500 rounded-full mr-2';
        if (this.statusDetails) {
          this.statusDetails.textContent = 'Domain configuration needs attention';
          this.statusDetails.className = 'text-xs text-red-600 mt-1';
        }
      }
    }
  }

  showDetailedStatus(data) {
    if (!this.detailsExpanded) return;
    
    // Update DNS status
    this.updateCheckStatus('dns', data.dns_check.verified, 
      data.dns_check.verified ? `CNAME points to ${data.dns_check.target}` : (data.dns_check.error || 'CNAME record not found')
    );
    
    // Update Render status
    this.updateCheckStatus('render', data.render_check.verified,
      data.render_check.verified ? 'Domain verified in Render' : (data.render_check.error || 'Domain not found in Render')
    );
    
    // Update Health status
    this.updateCheckStatus('health', data.health_check.healthy,
      data.health_check.healthy && data.health_check.status_code ? 
        `HTTP ${data.health_check.status_code} (${data.health_check.response_time}s)` : 
        (data.health_check.error || 'Health check failed')
    );
    
    // Show detailed status
    this.detailsExpanded.classList.remove('hidden');
  }

  updateCheckStatus(checkType, isSuccess, message) {
    const indicator = document.getElementById(`${checkType}-check-indicator`);
    const text = document.getElementById(`${checkType}-check-text`);
    
    if (!indicator || !text) return;
    
    if (isSuccess) {
      indicator.className = 'w-2 h-2 bg-green-500 rounded-full mr-2';
      text.textContent = message;
      text.className = 'text-green-600 mt-1';
    } else {
      indicator.className = 'w-2 h-2 bg-red-500 rounded-full mr-2';
      text.textContent = message;
      text.className = 'text-red-600 mt-1';
    }
  }

  showDomainStatusError(message) {
    if (this.statusText) {
      this.statusText.textContent = 'Status check failed';
    }
    
    if (this.statusDetails) {
      this.statusDetails.textContent = message;
      this.statusDetails.className = 'text-xs text-red-600 mt-1';
    }
    
    if (this.statusIndicator) {
      this.statusIndicator.className = 'w-3 h-3 bg-red-500 rounded-full mr-2';
    }
  }

  // Auto-check domain status on page load for custom domains
  initializeDomainStatusChecker(isActive) {
    if (this.autoInitDone) return;
    this.autoInitDone = true;
    if (!this.domainStatusContainer) return;
    
    // Always run a live check on load to avoid stale banners
    setTimeout(() => this.checkDomainStatus(), 500);
  }

  getCheckDomainStatusUrl() {
    // This should be set by the Rails view
    return window.domainStatusCheckUrl || '/manage/settings/business/check_domain_status';
  }

  getFinalizeActivationUrl() {
    return window.finalizeDomainActivationUrl || '/manage/settings/business/finalize_domain_activation';
  }

  getCsrfToken() {
    const meta = document.querySelector('meta[name="csrf-token"]');
    return meta ? meta.getAttribute('content') : '';
  }
}

// Global functions for backward compatibility and initialization
let domainStatusChecker;

function checkDomainStatus() {
  if (!domainStatusChecker) {
    domainStatusChecker = new DomainStatusChecker();
  }
  domainStatusChecker.checkDomainStatus();
}

function initializeDomainStatusChecker(isActive = false) {
  if (!domainStatusChecker) {
    domainStatusChecker = new DomainStatusChecker();
  }
  domainStatusChecker.initializeDomainStatusChecker(isActive);
}

// Auto-initialize on DOM ready
document.addEventListener('DOMContentLoaded', () => {
  if (document.getElementById('domain-status-container')) {
    if (!domainStatusChecker) {
      domainStatusChecker = new DomainStatusChecker();
    }
    domainStatusChecker.initializeDomainStatusChecker(!!window.domainIsActive);
  }
});

// Turbo compatibility
document.addEventListener('turbo:load', () => {
  if (document.getElementById('domain-status-container')) {
    if (!domainStatusChecker) {
      domainStatusChecker = new DomainStatusChecker();
    }
    domainStatusChecker.initializeDomainStatusChecker(!!window.domainIsActive);
  }
});

// Export for module systems
if (typeof module !== 'undefined' && module.exports) {
  module.exports = DomainStatusChecker;
}
