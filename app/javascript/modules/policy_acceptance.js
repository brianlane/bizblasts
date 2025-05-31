// Policy Acceptance Modal Handler
class PolicyAcceptance {
  constructor() {
    this.modal = document.getElementById('policy-acceptance-modal');
    this.acceptAllBtn = document.getElementById('accept-all-policies');
    this.policiesContainer = document.getElementById('policies-to-accept');
    this.acceptedPolicies = new Set();
    
    if (this.modal) {
      this.bindEvents();
      this.checkPolicyStatus();
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
  }
  
  async checkPolicyStatus() {
    try {
      const response = await fetch('/policy_status', {
        headers: {
          'Accept': 'application/json',
          'X-CSRF-Token': this.getCSRFToken()
        }
      });
      
      if (!response.ok) {
        throw new Error('Failed to check policy status');
      }
      
      const data = await response.json();
      
      if (data.requires_policy_acceptance && data.missing_policies.length > 0) {
        this.showPolicyModal(data.missing_policies);
      }
    } catch (error) {
      console.error('Error checking policy status:', error);
    }
  }
  
  showPolicyModal(missingPolicies) {
    if (!this.policiesContainer) return;
    
    this.policiesContainer.innerHTML = '';
    this.acceptedPolicies.clear();
    
    missingPolicies.forEach(policy => {
      const policyElement = this.createPolicyElement(policy);
      this.policiesContainer.appendChild(policyElement);
    });
    
    this.updateAcceptAllButton();
    this.modal.classList.remove('hidden');
    document.body.style.overflow = 'hidden'; // Prevent background scrolling
    
    // Focus on first checkbox for accessibility
    const firstCheckbox = this.policiesContainer.querySelector('.policy-checkbox');
    if (firstCheckbox) {
      firstCheckbox.focus();
    }
  }
  
  createPolicyElement(policy) {
    const div = document.createElement('div');
    div.className = 'border border-gray-200 rounded-lg p-4';
    
    const descriptions = {
      'privacy_policy': 'How BizBlasts handles your payment/booking data',
      'terms_of_service': 'Payment processing, booking platform rules, and billing terms',
      'acceptable_use_policy': 'Platform usage rules and booking system guidelines',
      'return_policy': 'Subscription cancellation/refund terms'
    };
    
    div.innerHTML = `
      <div class="flex items-start space-x-3">
        <input type="checkbox" 
               class="policy-checkbox mt-1 h-4 w-4 text-blue-600 border-gray-300 rounded focus:ring-blue-500" 
               data-policy-type="${policy.policy_type}"
               data-policy-version="${policy.version}"
               id="policy-${policy.policy_type}">
        <div class="flex-1">
          <label for="policy-${policy.policy_type}" class="text-sm font-medium text-gray-900 cursor-pointer">
            ${policy.policy_name}
          </label>
          <p class="text-xs text-gray-500 mt-1">
            ${descriptions[policy.policy_type] || 'Please review and accept this policy.'}
            <a href="${policy.policy_path}" target="_blank" class="text-blue-600 hover:underline ml-1">
              Read ${policy.policy_name} →
            </a>
          </p>
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
      this.acceptAllBtn.textContent = `Accept All (${acceptedCount}/${totalPolicies})`;
      this.acceptAllBtn.className = 'w-full inline-flex justify-center rounded-md border border-transparent shadow-sm px-4 py-2 bg-gray-400 text-base font-medium text-white cursor-not-allowed sm:ml-3 sm:w-auto sm:text-sm';
    } else {
      this.acceptAllBtn.textContent = 'Accept All & Continue';
      this.acceptAllBtn.className = 'w-full inline-flex justify-center rounded-md border border-transparent shadow-sm px-4 py-2 bg-blue-600 text-base font-medium text-white hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 sm:ml-3 sm:w-auto sm:text-sm';
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
      console.error('Error recording policy acceptance:', error);
      alert('An error occurred while saving your policy acceptance. Please try again.');
      
      // Reset button state
      this.updateAcceptAllButton();
    }
  }
  
  showSuccessMessage() {
    // Create a temporary success message
    const message = document.createElement('div');
    message.className = 'fixed top-4 right-4 bg-green-500 text-white px-6 py-3 rounded-lg shadow-lg z-60';
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
    }
    document.body.style.overflow = ''; // Restore scrolling
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