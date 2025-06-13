# frozen_string_literal: true

# SECURITY FIX: Enhanced security logging and monitoring

module SecurityLogging
  # Log security events with standardized format
  def self.log_security_event(event_type, details = {}, level = :info)
    timestamp = Time.current.utc.iso8601
    event_data = {
      timestamp: timestamp,
      type: event_type,
      details: details,
      environment: Rails.env
    }
    
    case level
    when :warn, :warning
      Rails.logger.warn "[SECURITY] #{event_data}"
    when :error
      Rails.logger.error "[SECURITY] #{event_data}"
    else
      Rails.logger.info "[SECURITY] #{event_data}"
    end
  end

  # Log authentication events
  def self.log_auth_event(user_id, event, ip_address, user_agent = nil)
    details = {
      user_id: user_id,
      ip_address: ip_address,
      user_agent: user_agent&.truncate(255)
    }
    
    log_security_event("auth_#{event}", details, 
                      %w[login_failure password_reset_abuse].include?(event.to_s) ? :warn : :info)
  end

  # Log authorization failures
  def self.log_authorization_failure(user_id, resource, action, ip_address)
    details = {
      user_id: user_id,
      resource: resource,
      action: action,
      ip_address: ip_address
    }
    
    log_security_event('authorization_denied', details, :warn)
  end

  # Log data access events for sensitive operations
  def self.log_data_access(user_id, resource_type, resource_id, action, ip_address)
    details = {
      user_id: user_id,
      resource_type: resource_type,
      resource_id: resource_id,
      action: action,
      ip_address: ip_address
    }
    
    log_security_event('data_access', details)
  end

  # Log security configuration changes
  def self.log_config_change(user_id, setting, old_value, new_value, ip_address)
    details = {
      user_id: user_id,
      setting: setting,
      old_value: mask_sensitive_value(old_value),
      new_value: mask_sensitive_value(new_value),
      ip_address: ip_address
    }
    
    log_security_event('config_change', details, :warn)
  end

  private

  def self.mask_sensitive_value(value)
    return '[REDACTED]' if sensitive_field?(value)
    value.to_s.truncate(100)
  end

  def self.sensitive_field?(value)
    return false unless value.is_a?(String)
    
    sensitive_patterns = %w[password token secret key api_key]
    sensitive_patterns.any? { |pattern| value.downcase.include?(pattern) }
  end
end

# Hook into Devise for authentication logging
if defined?(Devise)
  Warden::Manager.after_set_user do |user, auth, opts|
    SecurityLogging.log_auth_event(
      user.id,
      'login_success',
      auth.request.remote_ip,
      auth.request.user_agent
    )
  end

  Warden::Manager.after_failed_fetch do |user, auth, opts|
    # Skip logging for health check endpoints to avoid false security warnings
    health_check_paths = ['/healthcheck', '/up', '/db-check', '/maintenance']
    return if health_check_paths.include?(auth.request.path)
    
    # Skip logging for Render's health check user agent
    return if auth.request.user_agent&.include?('Render/1.0')
    
    SecurityLogging.log_auth_event(
      nil,
      'login_failure',
      auth.request.remote_ip,
      auth.request.user_agent
    )
  end
end

# Hook into Pundit for authorization logging
if defined?(Pundit)
  module PunditSecurityLogging
    def authorize(record, query = nil, policy_class: nil)
      result = super
      
      # Log successful authorizations for sensitive resources
      if sensitive_resource?(record)
        SecurityLogging.log_data_access(
          current_user&.id,
          record.class.name,
          record.respond_to?(:id) ? record.id : nil,
          query || action_name,
          request.remote_ip
        )
      end
      
      result
    rescue Pundit::NotAuthorizedError => e
      # Log authorization failures
      SecurityLogging.log_authorization_failure(
        current_user&.id,
        record.class.name,
        query || action_name,
        request.remote_ip
      )
      
      raise e
    end

    private

    def sensitive_resource?(record)
      # Define which resources should have access logged
      sensitive_classes = %w[User Business DiscountCode ReferralProgram LoyaltyTransaction]
      sensitive_classes.include?(record.class.name)
    end
  end

  # Include in ApplicationController to add security logging to Pundit
  ActiveSupport.on_load(:action_controller) do
    prepend PunditSecurityLogging if respond_to?(:authorize)
  end
end 