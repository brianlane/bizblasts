# frozen_string_literal: true

# SecurityMonitoring - Concern for monitoring security events in controllers
module SecurityMonitoring
  extend ActiveSupport::Concern

  included do
    before_action :log_suspicious_activity
    around_action :monitor_cross_tenant_access
  end

  private

  def log_suspicious_activity
    # Check for suspicious patterns in requests
    suspicious_patterns = [
      # SQL injection attempts
      /(\bUNION\b|\bSELECT\b|\bINSERT\b|\bDELETE\b|\bDROP\b)/i,
      # Path traversal attempts
      /\.\.\//,
      # XSS attempts
      /<script|javascript:|onload=/i,
      # Command injection attempts
      /(\||;|`|\$\()/
    ]

    request_params = params.to_s
    request_path = request.fullpath

    suspicious_patterns.each do |pattern|
      if request_params.match?(pattern) || request_path.match?(pattern)
        SecureLogger.security_event('suspicious_request', {
          user_id: current_user&.id,
          ip: request.remote_ip,
          path: request.fullpath,
          method: request.method,
          user_agent: request.user_agent&.truncate(100),
          pattern_matched: pattern.inspect
        })
        break
      end
    end
  end

  def monitor_cross_tenant_access
    original_tenant = ActsAsTenant.current_tenant
    
    yield
    
    # Check if tenant changed unexpectedly during request
    if ActsAsTenant.current_tenant != original_tenant
      SecureLogger.security_event('tenant_context_change', {
        user_id: current_user&.id,
        ip: request.remote_ip,
        path: request.fullpath,
        original_tenant: original_tenant&.id,
        new_tenant: ActsAsTenant.current_tenant&.id
      })
    end
  rescue => e
    # Log any errors that might indicate security issues
    if e.message.include?('tenant') || e.message.include?('permission') || e.message.include?('authorized')
      SecureLogger.security_event('security_error', {
        user_id: current_user&.id,
        ip: request.remote_ip,
        path: request.fullpath,
        error: e.class.name,
        message: e.message.truncate(200)
      })
    end
    raise
  end

  def check_for_enumeration_attack
    # Monitor for rapid sequential requests that might indicate enumeration
    cache_key = "enumeration_check_#{request.remote_ip}"
    request_count = Rails.cache.increment(cache_key, 1, expires_in: 1.minute) || 1
    
    Rails.cache.write("#{cache_key}_requests", request_count, expires_in: 1.minute) if request_count == 1

    if request_count > 20 # More than 20 requests per minute from same IP
      SecureLogger.security_event('possible_enumeration_attack', {
        ip: request.remote_ip,
        path: request.fullpath,
        request_count: request_count,
        user_agent: request.user_agent&.truncate(100)
      })
    end
  end

  def log_sensitive_action(action_type, resource = nil)
    SecureLogger.security_event('sensitive_action', {
      user_id: current_user&.id,
      ip: request.remote_ip,
      action: action_type,
      resource: resource&.class&.name,
      resource_id: resource&.id,
      path: request.fullpath
    })
  end
end