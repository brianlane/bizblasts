class CustomerLinker
  # Service to link User accounts to TenantCustomer records
  # Handles guest checkout -> user signup flow and prevents duplicates
  
  def initialize(business)
    @business = business
  end
  
  # Find or create a TenantCustomer for the given user
  # Links the user if not already linked
  def link_user_to_customer(user, customer_attributes = {})
    raise ArgumentError, "User must be a client" unless user.client?
    
    # First try to find existing customer by user_id
    customer = @business.tenant_customers.find_by(user_id: user.id)
    if customer
      # Always sync user data to existing linked customer to keep phone/preferences current
      sync_user_data_to_customer(user, customer)
      return customer
    end
    
    # Look for unlinked customer with same email
    email = user.email.downcase.strip
    unlinked_customer = @business.tenant_customers.find_by(
      email: email,
      user_id: nil
    )
    
    if unlinked_customer
      # Link the existing customer to this user
      unlinked_customer.update!(user_id: user.id)
      sync_user_data_to_customer(user, unlinked_customer)
      return unlinked_customer
    end
    
    # Check for existing linked customer with same email (different user)
    existing_customer = @business.tenant_customers.find_by(email: email)
    if existing_customer&.user_id && existing_customer.user_id != user.id
      Rails.logger.error "[CUSTOMER_LINKER] Email conflict: #{email} already linked to different user #{existing_customer.user_id} in business #{@business.id}, cannot link to user #{user.id}"                                                
      
      # This indicates a data integrity issue that should be investigated
      # Rather than creating invalid email addresses, raise a typed error
      raise EmailConflictError.new(
        "Email #{email} is already associated with a different customer account in this business. Please contact support for assistance.",
        email: email,
        business_id: @business.id,
        existing_user_id: existing_customer.user_id,
        attempted_user_id: user.id
      )
    end
    
    # Create new customer linked to user
    customer_data = {
      email: email,
      user_id: user.id,
      first_name: user.first_name,
      last_name: user.last_name,
      phone: user.phone,
      phone_opt_in: user.respond_to?(:phone_opt_in?) ? user.phone_opt_in? : false,
      phone_opt_in_at: user.respond_to?(:phone_opt_in_at) ? user.phone_opt_in_at : nil
    }.merge(customer_attributes)
    
    @business.tenant_customers.create!(customer_data)
  end
  
  # Find or create customer for guest checkout (no user account)
  def find_or_create_guest_customer(email, customer_attributes = {})
    email = email.downcase.strip
    
    customer = @business.tenant_customers.find_by(email: email, user_id: nil)
    if customer
      # Update existing guest customer with any new attributes provided
      updates = {}
      %i[first_name last_name phone].each do |attr|
        value = customer_attributes[attr]
        updates[attr] = value if value.present? && customer.send(attr) != value
      end

      # Handle phone_opt_in updates
      if customer_attributes.key?(:phone_opt_in)
        opt_in_value = customer_attributes[:phone_opt_in]
        new_opt_in = (opt_in_value == true || opt_in_value == "true")

        if customer.phone_opt_in? != new_opt_in
          updates[:phone_opt_in] = new_opt_in
          updates[:phone_opt_in_at] = new_opt_in ? Time.current : nil
        end
      end

      customer.update!(updates) if updates.any?
      return customer
    end
    
    # Check if email belongs to an existing linked customer
    linked_customer = @business.tenant_customers.find_by(email: email)
    if linked_customer&.user_id
      Rails.logger.info "[CUSTOMER_LINKER] Guest checkout with email #{email} matches existing linked customer #{linked_customer.id}"
      return linked_customer
    end
    
    customer_data = {
      email: email,
      user_id: nil
    }.merge(customer_attributes)

    # Set phone_opt_in_at if phone_opt_in is true
    if customer_data[:phone_opt_in] == true || customer_data[:phone_opt_in] == "true"
      customer_data[:phone_opt_in] = true
      customer_data[:phone_opt_in_at] = Time.current
    else
      customer_data[:phone_opt_in] = false
      customer_data[:phone_opt_in_at] = nil
    end

    @business.tenant_customers.create!(customer_data)
  end
  
  
  # Sync user data to their linked customer
  def sync_user_data_to_customer(user, customer = nil)
    customer ||= @business.tenant_customers.find_by(user_id: user.id)
    return unless customer
    
    updates = {}
    
    # Sync basic info if customer values are blank
    updates[:first_name] = user.first_name if customer.first_name.blank? && user.first_name.present?
    updates[:last_name] = user.last_name if customer.last_name.blank? && user.last_name.present?
    
    # Sync phone from user to customer - prioritize user's phone since they actively manage it
    if user.phone.present? && customer.phone != user.phone
      updates[:phone] = user.phone
      # Sync opt-in status from user when phone changes
      if user.respond_to?(:phone_opt_in?)
        updates[:phone_opt_in] = user.phone_opt_in?
        updates[:phone_opt_in_at] = user.phone_opt_in? ?
          (user.respond_to?(:phone_opt_in_at) ? user.phone_opt_in_at : Time.current) :
          nil
      end
    end
    
    # Sync email if different (case-insensitive). to_s ensures no nil errors.
    if customer.email.to_s.casecmp?(user.email.to_s) == false
      updates[:email] = user.email.downcase.strip
    end
    
    customer.update!(updates) if updates.any?
  end
  
end
