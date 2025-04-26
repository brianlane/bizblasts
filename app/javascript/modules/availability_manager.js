// A module to handle calendar availability functionality
// This is used by both base domain and subdomain controllers

export default class AvailabilityManager {
  // Initialize with base URL for API endpoints
  constructor(options = {}) {
    this.baseUrl = options.baseUrl || '';
    this.isSubdomain = options.isSubdomain || false;
    this.staffId = options.staffId;
    this.serviceId = options.serviceId;
    this.debug = options.debug || false;
  }
  
  // Set the current service and staff IDs
  setIds(serviceId, staffId) {
    this.serviceId = serviceId;
    this.staffId = staffId;
  }
  
  // Log method for debug statements
  log(...args) {
    if (this.debug) {
      console.log('[AvailabilityManager]', ...args);
    }
  }
  
  // Fetch available slots for a date range
  fetchDateRange(startDate, endDate) {
    if (!this.staffId || !this.serviceId) {
      this.log('Missing staff or service ID');
      return Promise.reject('Missing staff or service ID');
    }
    
    const url = this.buildUrl('/available_slots', {
      staff_member_id: this.staffId,
      service_id: this.serviceId,
      start_date: startDate,
      end_date: endDate
    });
    
    this.log(`Fetching date range ${startDate} to ${endDate}`);
    
    return fetch(url, {
      headers: {
        'Accept': 'application/json'
      }
    })
    .then(response => {
      if (!response.ok) {
        throw new Error(`Server error: ${response.status}`);
      }
      return response.json();
    })
    .catch(error => {
      console.error('Error fetching date range:', error);
      throw error;
    });
  }
  
  // Fetch available slots for a specific date
  fetchDate(date) {
    if (!this.staffId || !this.serviceId) {
      this.log('Missing staff or service ID');
      return Promise.reject('Missing staff or service ID');
    }
    
    const url = this.buildUrl('/available_slots', {
      staff_member_id: this.staffId,
      service_id: this.serviceId,
      date: date
    });
    
    this.log(`Fetching single date ${date}`);
    
    return fetch(url, {
      headers: {
        'Accept': 'application/json'
      }
    })
    .then(response => {
      if (!response.ok) {
        throw new Error(`Server error: ${response.status}`);
      }
      return response.json();
    })
    .catch(error => {
      console.error('Error fetching date:', error);
      throw error;
    });
  }
  
  // Fetch staff availability for a service on a date
  fetchStaffAvailability(date, serviceId = null) {
    const requestServiceId = serviceId || this.serviceId;
    
    if (!requestServiceId) {
      this.log('Missing service ID');
      return Promise.reject('Missing service ID');
    }
    
    const url = this.buildUrl('/staff_availability', {
      service_id: requestServiceId,
      date: date
    });
    
    this.log(`Fetching staff availability for ${date}`);
    
    return fetch(url, {
      headers: {
        'Accept': 'application/json'
      }
    })
    .then(response => {
      if (!response.ok) {
        throw new Error(`Server error: ${response.status}`);
      }
      return response.json();
    })
    .catch(error => {
      console.error('Error fetching staff availability:', error);
      throw error;
    });
  }
  
  // Format a date string for display
  formatDate(date) {
    const options = { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' };
    if (typeof date === 'string') {
      date = new Date(date);
    }
    return date.toLocaleDateString(undefined, options);
  }
  
  // Format a time string for display
  formatTime(timeString) {
    const time = new Date(timeString);
    return time.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
  }
  
  // Build a URL with query parameters
  buildUrl(path, params = {}) {
    // Determine the base path from the type of booking system
    const basePath = this.isSubdomain ? 
      '/tenant' + path : 
      '/bookings' + path;
    
    // Build query string from params
    const queryParams = Object.entries(params)
      .filter(([_, value]) => value !== null && value !== undefined)
      .map(([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(value)}`)
      .join('&');
    
    return `${this.baseUrl}${basePath}${queryParams ? '?' + queryParams : ''}`;
  }
  
  // Generate a booking URL based on time slot
  getBookingUrl(slot, serviceId = null, staffId = null) {
    const requestServiceId = serviceId || this.serviceId;
    const requestStaffId = staffId || this.staffId;
    
    if (!requestServiceId || !requestStaffId) {
      this.log('Missing service or staff ID for booking URL');
      return '#';
    }
    
    const startTime = new Date(slot.start_time);
    const date = startTime.toISOString().split('T')[0];
    const time = startTime.toTimeString().substring(0, 5);
    
    const path = this.isSubdomain ? 
      '/book' : 
      '/bookings/new';
    
    return `${this.baseUrl}${path}?service_id=${requestServiceId}&staff_member_id=${requestStaffId}&date=${date}&start_time=${time}`;
  }
} 