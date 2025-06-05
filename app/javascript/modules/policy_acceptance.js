// Policy Acceptance Modal Handler
class PolicyAcceptance {
  constructor() {
    this.modal = document.getElementById('policy-acceptance-modal');
    this.acceptAllBtn = document.getElementById('accept-all-policies');
    this.policiesContainer = document.getElementById('policies-to-accept');
    this.acceptedPolicies = new Set();
    this.debugMode = window.location.search.includes('debug_policy=true');
    
    if (this.modal) {
      this.bindEvents();
      // Add small delay to ensure DOM is fully ready
      setTimeout(() => {
        this.checkPolicyStatus();
      }, 100);
    } else {
      console.warn('[PolicyAcceptance] Modal element not found in DOM');
    }
  }
  
  bindEvents() {
    
    // Handle individual policy acceptance
    document.addEventListener('change', (e) => {
      if (e.target.matches('.policy-checkbox')) {
        this.handlePolicyCheck(e.target);
      }
    });
    
    // Handle accept all button
    this.acceptAllBtn?.addEventListener('click', () => {
      this.acceptAllPolicies();
    });
    
    // Prevent modal close unless all policies accepted
    this.modal?.addEventListener('click', (e) => {
      if (e.target === this.modal) {
        e.preventDefault();
      }
    });
    
    // Close modal with Escape key only if all policies accepted
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && !this.modal.classList.contains('hidden')) {
        const totalPolicies = this.policiesContainer?.querySelectorAll('.policy-checkbox').length || 0;
        const acceptedCount = this.acceptedPolicies.size;
        
        if (acceptedCount >= totalPolicies && totalPolicies > 0) {
          this.closePolicyModal();
        }
      }
    });
    
    // Add manual trigger for debugging
    if (this.debugMode) {
      window.showPolicyModal = () => this.showPolicyModal([
        { policy_type: 'privacy_policy', policy_name: 'Privacy Policy', policy_path: '/privacypolicy', version: 'v1.0' }
      ]);
    }
  }
  
  async checkPolicyStatus() {
    
    try {
      const token = this.getCSRFToken();
      
      const response = await fetch('/policy_status', {
        headers: {
          'Accept': 'application/json',
          'X-CSRF-Token': token
        }
      });
      
      if (!response.ok) {
        if (response.status === 401) {
          return;
        }
        throw new Error(`Failed to check policy status: ${response.status} ${response.statusText}`);
      }
      
      const data = await response.json();
      
      if (data.requires_policy_acceptance && data.missing_policies.length > 0) {
        this.showPolicyModal(data.missing_policies);
      } else {
      }
    } catch (error) {
      console.error('[PolicyAcceptance] Error checking policy status:', error);
      
      // If there's an error but we're in debug mode, show a test modal
      if (this.debugMode) {
        this.showPolicyModal([
          { policy_type: 'privacy_policy', policy_name: 'Privacy Policy', policy_path: '/privacypolicy', version: 'v1.0' }
        ]);
      }
    }
  }
  
  showPolicyModal(missingPolicies) {
    
    if (!this.policiesContainer) {
      console.error('[PolicyAcceptance] Policies container not found');
      return;
    }
    
    this.policiesContainer.innerHTML = '';
    this.acceptedPolicies.clear();
    
    missingPolicies.forEach(policy => {
      const policyElement = this.createPolicyElement(policy);
      this.policiesContainer.appendChild(policyElement);
    });
    
    this.updateAcceptAllButton();
    
    // Remove hidden class and add display debugging
    this.modal.classList.remove('hidden');
    
    // Force display and prevent background scrolling
    this.modal.style.display = 'block';
    document.body.style.overflow = 'hidden';
    
    // Additional debugging
    
    // Focus on first checkbox for accessibility
    setTimeout(() => {
      const firstCheckbox = this.policiesContainer.querySelector('.policy-checkbox');
      if (firstCheckbox) {
        firstCheckbox.focus();
      }
    }, 100);
    
    // Add visible indicator for debugging
    if (this.debugMode) {
      this.modal.style.border = '5px solid red';
    }
  }
  
  createPolicyElement(policy) {
    const div = document.createElement('div');
    div.className = 'border border-gray-200 rounded-lg p-4 hover:border-blue-300 transition-colors';
    
    const descriptions = {
      'privacy_policy': 'How BizBlasts handles your payment/booking data',
      'terms_of_service': 'Payment processing, booking platform rules, and billing terms',
      'acceptable_use_policy': 'Platform usage rules and booking system guidelines',
      'return_policy': 'Subscription cancellation/refund terms'
    };
    
    div.innerHTML = `
      <div class="flex items-start space-x-3">
        <input type="checkbox" 
               class="policy-checkbox mt-1 h-5 w-5 text-blue-600 border-gray-300 rounded focus:ring-blue-500 focus:ring-offset-2" 
               data-policy-type="${policy.policy_type}"
               data-policy-version="${policy.version}"
               id="policy-${policy.policy_type}">
        <div class="flex-1">
          <label for="policy-${policy.policy_type}" class="text-base font-medium text-gray-900 cursor-pointer hover:text-blue-700 transition-colors">
            I agree to the ${policy.policy_name}
          </label>
          <p class="text-sm text-gray-600 mt-1">
            ${descriptions[policy.policy_type] || 'Please review and accept this policy.'}
          </p>
          <a href="${policy.policy_path}" target="_blank" class="inline-block mt-2 text-sm text-blue-600 hover:text-blue-800 hover:underline font-medium">
            Read ${policy.policy_name} →
          </a>
        </div>
      </div>
    `;
    
    return div;
  }
  
  handlePolicyCheck(checkbox) {
    const policyType = checkbox.dataset.policyType;
    
    if (checkbox.checked) {
      this.acceptedPolicies.add(policyType);
    } else {
      this.acceptedPolicies.delete(policyType);
    }
    
    this.updateAcceptAllButton();
  }
  
  updateAcceptAllButton() {
    if (!this.acceptAllBtn || !this.policiesContainer) return;
    
    const totalPolicies = this.policiesContainer.querySelectorAll('.policy-checkbox').length;
    const acceptedCount = this.acceptedPolicies.size;
    
    
    this.acceptAllBtn.disabled = acceptedCount < totalPolicies;
    
    if (acceptedCount < totalPolicies) {
      this.acceptAllBtn.textContent = `Accept All Policies (${acceptedCount}/${totalPolicies})`;
      this.acceptAllBtn.className = 'w-full inline-flex justify-center rounded-lg border border-transparent shadow-sm px-6 py-3 bg-gray-300 text-base font-medium text-gray-600 cursor-not-allowed sm:ml-3 sm:w-auto sm:text-sm';
    } else {
      this.acceptAllBtn.textContent = 'Accept All & Continue';
      this.acceptAllBtn.className = 'w-full inline-flex justify-center rounded-lg border border-transparent shadow-sm px-6 py-3 bg-blue-600 text-base font-medium text-white hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 transition-colors sm:ml-3 sm:w-auto sm:text-sm';
    }
  }
  
  async acceptAllPolicies() {
    
    if (!this.policiesContainer) return;
    
    const checkedBoxes = this.policiesContainer.querySelectorAll('.policy-checkbox:checked');
    const acceptances = {};
    
    checkedBoxes.forEach(checkbox => {
      acceptances[checkbox.dataset.policyType] = '1';
    });
    
    
    try {
      this.acceptAllBtn.disabled = true;
      this.acceptAllBtn.textContent = 'Processing...';
      
      const response = await fetch('/policy_acceptances/bulk', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-CSRF-Token': this.getCSRFToken()
        },
        body: JSON.stringify({ policy_acceptances: acceptances })
      });
      
      const data = await response.json();
      
      if (data.success) {
        this.closePolicyModal();
        
        // Show success message
        this.showSuccessMessage();
        
        // Redirect to intended destination or reload
        const afterPath = sessionStorage.getItem('after_policy_acceptance_path');
        if (afterPath && afterPath !== window.location.pathname) {
          sessionStorage.removeItem('after_policy_acceptance_path');
          window.location.href = afterPath;
        } else {
          // Small delay before reload to show success message
          setTimeout(() => {
            window.location.reload();
          }, 1000);
        }
      } else {
        throw new Error(data.error || 'Failed to record policy acceptance');
      }
    } catch (error) {
      console.error('[PolicyAcceptance] Error recording policy acceptance:', error);
      alert('An error occurred while saving your policy acceptance. Please try again.');
      
      // Reset button state
      this.updateAcceptAllButton();
    }
  }
  
  showSuccessMessage() {
    // Create a temporary success message
    const message = document.createElement('div');
    message.className = 'fixed top-4 right-4 bg-green-500 text-white px-6 py-3 rounded-lg shadow-lg z-[10000]';
    message.textContent = 'Policies accepted successfully!';
    document.body.appendChild(message);
    
    
    // Remove after 3 seconds
    setTimeout(() => {
      if (message.parentNode) {
        message.parentNode.removeChild(message);
      }
    }, 3000);
  }
  
  closePolicyModal() {
    
    if (this.modal) {
      this.modal.classList.add('hidden');
      this.modal.style.display = 'none';
    }
    document.body.style.overflow = ''; // Restore scrolling
    
    // Remove debug border if present
    if (this.debugMode && this.modal) {
      this.modal.style.border = '';
    }
  }
  
  getCSRFToken() {
    const token = document.querySelector('[name="csrf-token"]');
    return token ? token.content : '';
  }
}

// Initialize when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
  new PolicyAcceptance();
});

// Also initialize on Turbo navigation
document.addEventListener('turbo:load', () => {
  new PolicyAcceptance();
});

export default PolicyAcceptance; 