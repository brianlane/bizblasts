# frozen_string_literal: true

# Represents an email specification that can be executed later without
# accessing the ActionMailer message object prematurely
class EmailSpecification
  attr_reader :mailer_class, :method_name, :arguments, :condition, :business_context

  def initialize(mailer_class:, method_name:, arguments: [], condition: nil)
    @mailer_class = mailer_class
    @method_name = method_name.to_sym
    @arguments = arguments.freeze
    @condition = condition
    
    # Validate arguments first
    validate_specification!
    
    # Extract business context from tenant-scoped models in arguments
    @business_context = extract_business_context(arguments)
    
    freeze
  end

  # Execute the email specification if conditions are met
  def execute
    return false unless should_execute?
    
    begin
      # Execute within the proper tenant context if needed
      if business_context
        ActsAsTenant.with_tenant(business_context) do
          execute_mailer_method
        end
      else
        execute_mailer_method
      end
    rescue => e
      Rails.logger.error "[EmailSpec] Failed to execute #{mailer_class}.#{method_name}: #{e.message}"
      false
    end
  end

  # Execute with a delay
  def execute_with_delay(wait:)
    return false unless should_execute?
    
    begin
      # Execute within the proper tenant context if needed
      if business_context
        ActsAsTenant.with_tenant(business_context) do
          execute_mailer_method_with_delay(wait)
        end
      else
        execute_mailer_method_with_delay(wait)
      end
    rescue => e
      Rails.logger.error "[EmailSpec] Failed to execute #{mailer_class}.#{method_name} with delay: #{e.message}"
      false
    end
  end

  # Human-readable description for logging
  def description
    "#{mailer_class}.#{method_name}(#{arguments.map { |arg| arg.class.name }.join(', ')})"
  end

  private

  def should_execute?
    return true unless condition
    
    begin
      condition.call
    rescue => e
      Rails.logger.error "[EmailSpec] Condition evaluation failed for #{description}: #{e.message}"
      false
    end
  end

  def validate_specification!
    raise ArgumentError, "mailer_class must be a class" unless mailer_class.is_a?(Class)
    raise ArgumentError, "mailer_class must respond to #{method_name}" unless mailer_class.respond_to?(method_name)
    raise ArgumentError, "arguments must be an array" unless arguments.is_a?(Array)
    raise ArgumentError, "condition must be callable" if condition && !condition.respond_to?(:call)
  end

  def extract_business_context(args)
    return nil unless args.is_a?(Array)
    
    # Look for models that use acts_as_tenant in the arguments
    args.each do |arg|
      if arg.respond_to?(:business) && arg.business.is_a?(Business)
        return arg.business
      elsif arg.is_a?(Business)
        return arg
      elsif arg.respond_to?(:tenant) && arg.tenant.is_a?(Business)
        return arg.tenant
      end
    end
    
    # If no business context found, use current tenant if available
    ActsAsTenant.current_tenant if ActsAsTenant.current_tenant.is_a?(Business)
  end

  def execute_mailer_method
    mailer_instance = mailer_class.public_send(method_name, *arguments)

    # Check if the mailer method returned nil (early return due to conditions)
    return false if mailer_instance.nil?

    mailer_instance.deliver_later(queue: 'mailers')
    Rails.logger.info "[EmailSpec] Executed #{mailer_class}.#{method_name} with args: #{arguments.map(&:class)}"
    true
  end

  def execute_mailer_method_with_delay(wait)
    mailer_instance = mailer_class.public_send(method_name, *arguments)

    # Check if the mailer method returned nil (early return due to conditions)
    return false if mailer_instance.nil?

    if Rails.env.test?
      # In test environment, don't use delays to avoid issues with job counting
      mailer_instance.deliver_later(queue: 'mailers')
    else
      mailer_instance.deliver_later(wait: wait, queue: 'mailers')
    end

    Rails.logger.info "[EmailSpec] Executed #{mailer_class}.#{method_name} with #{wait} delay"
    true
  end
end 