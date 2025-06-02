# frozen_string_literal: true

# Builder for creating collections of email specifications with a fluent interface
class EmailCollectionBuilder
  def initialize
    @specifications = []
  end

  # Add an email without conditions
  def add_email(mailer_class, method_name, args = [])
    spec = EmailSpecification.new(
      mailer_class: mailer_class,
      method_name: method_name,
      arguments: args
    )
    @specifications << spec
    Rails.logger.debug "[EmailBuilder] Added #{spec.description}"
    self
  end

  # Add an email with a condition
  def add_conditional_email(mailer_class:, method_name:, args: [], condition:)
    spec = EmailSpecification.new(
      mailer_class: mailer_class,
      method_name: method_name,
      arguments: args,
      condition: condition
    )
    @specifications << spec
    Rails.logger.debug "[EmailBuilder] Added conditional #{spec.description}"
    self
  end

  # Add emails for order scenarios (helper method)
  def add_order_emails(order)
    # Business order notification email
    add_email(BusinessMailer, :new_order_notification, [order])
    
    # Conditional new customer email
    customer = order.tenant_customer
    if customer&.persisted?
      add_conditional_email(
        mailer_class: BusinessMailer,
        method_name: :new_customer_notification,
        args: [customer],
        condition: -> { customer_newly_created?(customer) }
      )
    end
    
    # Customer invoice email (if invoice exists)
    if order.invoice&.persisted?
      add_email(InvoiceMailer, :invoice_created, [order.invoice])
    end
    
    self
  end

  # Add emails for booking scenarios (helper method)
  def add_booking_emails(booking)
    # Business booking notification email
    add_email(BusinessMailer, :new_booking_notification, [booking])
    
    # Conditional new customer email
    customer = booking.tenant_customer
    if customer&.persisted?
      add_conditional_email(
        mailer_class: BusinessMailer,
        method_name: :new_customer_notification,
        args: [customer],
        condition: -> { customer_newly_created?(customer) }
      )
    end
    
    # Customer invoice email (if invoice exists)  
    if booking.invoice&.persisted?
      add_email(InvoiceMailer, :invoice_created, [booking.invoice])
    end
    
    self
  end

  # Build and return the email specifications collection
  def build
    specifications = @specifications.dup.freeze
    Rails.logger.info "[EmailBuilder] Built collection with #{specifications.count} email specifications"
    specifications
  end

  # Get count of specifications without building
  def count
    @specifications.count
  end

  # Clear all specifications
  def clear
    @specifications.clear
    self
  end

  private

  # Check if this customer was just created in this request
  def customer_newly_created?(customer)
    return false unless customer&.persisted?
    
    # Customer was created within the last 10 seconds (recent creation)
    customer.created_at > 10.seconds.ago
  end
end 