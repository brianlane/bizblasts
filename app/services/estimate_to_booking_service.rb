# frozen_string_literal: true

class EstimateToBookingService
  def initialize(estimate)
    @estimate = estimate
  end

  def call
    return @estimate.booking if @estimate.booking.present?

    ActiveRecord::Base.transaction do
      # Ensure tenant_customer exists before creating booking
      # If estimate has inline customer fields but no tenant_customer, create one
      ensure_tenant_customer!

      # Create Booking based on the estimate
      booking = Booking.create!(
        business: estimate.business,
        tenant_customer: estimate.tenant_customer,
        staff_member: find_staff_member,
        start_time: estimate.proposed_start_time || Time.current,
        end_time: calculate_end_time,
        service: primary_service,
        quantity: [total_quantity, 1].max, # Ensure minimum of 1
        amount: estimate.subtotal,
        original_amount: estimate.subtotal,
        discount_amount: 0,
        status: :pending
      )

      # Associate booking with estimate
      estimate.update!(booking: booking)

      # Create Invoice for the booking based on the remaining balance
      Invoice.create_from_estimate(estimate)

      # Reload booking to ensure invoice association is loaded in memory
      # Without this, booking.invoice returns nil even though the invoice was created
      booking.reload
      booking
    end
  end

  private

  attr_reader :estimate

  # Returns the primary service for the booking (first line item)
  def primary_service
    estimate.estimate_items.first&.service
  end

  # Finds an appropriate staff member for the booking
  # Priority: 1. Staff who can perform the primary service
  #           2. Any active staff member
  #           3. First staff member of the business
  def find_staff_member
    service = primary_service
    
    # Try to find a staff member who can perform this service
    if service.present?
      staff_for_service = estimate.business.staff_members.joins(:services).where(services: { id: service.id }).first
      return staff_for_service if staff_for_service.present?
    end
    
    # Fallback to first active staff member
    estimate.business.staff_members.first
  end

  # Calculates end_time: use proposed_end_time if present, otherwise calculate from service duration
  # Falls back to 60 minutes if no service duration available
  def calculate_end_time
    return estimate.proposed_end_time if estimate.proposed_end_time.present?
    
    start = estimate.proposed_start_time || Time.current
    duration = primary_service&.duration.to_i
    duration = 60 if duration <= 0 # Default to 1 hour if no duration
    start + duration.minutes
  end

  # Sum of all quantities in line items
  def total_quantity
    estimate.estimate_items.sum(&:qty)
  end

  # Ensures estimate has a tenant_customer, creating one from inline fields if needed
  # This prevents nil tenant_customer errors when creating bookings/invoices
  def ensure_tenant_customer!
    return if estimate.tenant_customer.present?

    # Create TenantCustomer from estimate's inline customer fields
    # Note: TenantCustomer only stores first_name, last_name, email, phone, and address
    # The estimate stores additional fields (city, state, zip) separately
    customer = estimate.business.tenant_customers.create!(
      first_name: estimate.first_name,
      last_name: estimate.last_name,
      email: estimate.email,
      phone: estimate.phone,
      address: [estimate.address, estimate.city, estimate.state, estimate.zip].compact.join(', ')
    )

    # Update estimate with the newly created customer
    estimate.update!(tenant_customer: customer)
  end
end