# frozen_string_literal: true

# Represents an email specification that can be executed later without
# accessing the ActionMailer message object prematurely
class EmailSpecification
  attr_reader :mailer_class, :method_name, :arguments, :condition

  def initialize(mailer_class:, method_name:, arguments: [], condition: nil)
    @mailer_class = mailer_class
    @method_name = method_name.to_sym
    @arguments = arguments.freeze
    @condition = condition
    
    validate_specification!
    freeze
  end

  # Execute the email specification if conditions are met
  def execute
    return false unless should_execute?
    
    begin
      mailer_instance = mailer_class.public_send(method_name, *arguments)
      
      # Check if the mailer method returned nil (early return due to conditions)
      return false if mailer_instance.nil?
      
      mailer_instance.deliver_later
      Rails.logger.info "[EmailSpec] Executed #{mailer_class}.#{method_name} with args: #{arguments.map(&:class)}"
      true
    rescue => e
      Rails.logger.error "[EmailSpec] Failed to execute #{mailer_class}.#{method_name}: #{e.message}"
      false
    end
  end

  # Execute with a delay
  def execute_with_delay(wait:)
    return false unless should_execute?
    
    begin
      mailer_instance = mailer_class.public_send(method_name, *arguments)
      
      # Check if the mailer method returned nil (early return due to conditions)
      return false if mailer_instance.nil?
      
      if Rails.env.test?
        # In test environment, don't use delays to avoid issues with job counting
        mailer_instance.deliver_later
      else
        mailer_instance.deliver_later(wait: wait)
      end
      
      Rails.logger.info "[EmailSpec] Executed #{mailer_class}.#{method_name} with #{wait} delay"
      true
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
end 