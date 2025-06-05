/**
 * Booking Policy Enforcer
 * 
 * This module enforces booking policies on the client side:
 * - max_advance_days: Restricts date selection beyond the allowed window
 * - min_duration_mins: Enforces minimum booking duration
 * - max_duration_mins: Enforces maximum booking duration
 */

export default class BookingPolicyEnforcer {
  constructor(options = {}) {
    this.debug = options.debug || false;
    this.policies = options.policies || {};
    this.dateField = options.dateField;
    this.timeField = options.timeField;
    this.durationField = options.durationField;
    
    this.log('BookingPolicyEnforcer initialized with policies:', this.policies);
    
    if (this.dateField) {
      this.applyDateRestrictions();
    }
    
    if (this.timeField && this.durationField) {
      this.applyDurationRestrictions();
    }
  }
  
  /**
   * Apply date restrictions based on max_advance_days policy
   */
  applyDateRestrictions() {
    if (!this.dateField) return;
    
    const maxAdvanceDays = this.policies.max_advance_days;
    if (maxAdvanceDays && maxAdvanceDays > 0) {
      // Calculate the maximum allowed date
      const today = new Date();
      const maxDate = new Date();
      maxDate.setDate(today.getDate() + maxAdvanceDays);
      
      // Set the max attribute on the date field
      const maxDateStr = this.formatDate(maxDate);
      this.dateField.setAttribute('max', maxDateStr);
      
      this.log(`Date restrictions applied: max=${maxDateStr}`);
      
      // Add event listener to validate date selection
      this.dateField.addEventListener('change', () => {
        const selectedDate = new Date(this.dateField.value);
        if (selectedDate > maxDate) {
          alert(`You can only book up to ${maxAdvanceDays} days in advance.`);
          this.dateField.value = maxDateStr;
        }
      });
    }
  }
  
  /**
   * Apply duration restrictions based on min_duration_mins and max_duration_mins policies
   */
  applyDurationRestrictions() {
    if (!this.timeField || !this.durationField) return;
    
    const minDuration = this.policies.min_duration_mins;
    const maxDuration = this.policies.max_duration_mins;
    
    if (minDuration && minDuration > 0) {
      this.durationField.setAttribute('min', minDuration);
      this.log(`Minimum duration set: ${minDuration} minutes`);
    }
    
    if (maxDuration && maxDuration > 0) {
      this.durationField.setAttribute('max', maxDuration);
      this.log(`Maximum duration set: ${maxDuration} minutes`);
    }
    
    // Add event listener to validate duration selection
    this.durationField.addEventListener('change', () => {
      const selectedDuration = parseInt(this.durationField.value, 10);
      
      if (minDuration && selectedDuration < minDuration) {
        alert(`Minimum booking duration is ${minDuration} minutes.`);
        this.durationField.value = minDuration;
      }
      
      if (maxDuration && selectedDuration > maxDuration) {
        alert(`Maximum booking duration is ${maxDuration} minutes.`);
        this.durationField.value = maxDuration;
      }
    });
  }
  
  /**
   * Format a date as YYYY-MM-DD for input[type="date"] max attribute
   */
  formatDate(date) {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }
  
  /**
   * Log method for debugging
   */
  log(...args) {
    if (this.debug) {
    }
  }
} 