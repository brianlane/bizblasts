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
    return customer if customer
    
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
      # Rather than creating invalid email addresses, raise an error
      raise StandardError, "Email #{email} is already associated with a different customer account in this business. Please contact support for assistance."
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
    
    @business.tenant_customers.create!(customer_data)
  end
  
  # Merge duplicate customers for the same user in this business
  def merge_duplicate_customers_for_user(user)
    customers = @business.tenant_customers.where(user_id: user.id)
    return if customers.count <= 1
    
    Rails.logger.info "[CUSTOMER_LINKER] Merging #{customers.count} duplicate customers for user #{user.id} in business #{@business.id}"
    
    # Keep the oldest customer as primary
    primary_customer = customers.order(:created_at).first
    duplicate_customers = customers.where.not(id: primary_customer.id)
    
    ActiveRecord::Base.transaction do
      duplicate_customers.each do |duplicate|
        merge_customer_data(primary_customer, duplicate)
        
        # Move all associations to primary customer
        move_customer_associations(duplicate, primary_customer)
        
        # Delete the duplicate
        duplicate.destroy!
      end
      
      # Ensure primary customer has latest user data
      sync_user_data_to_customer(user, primary_customer)
    end
    
    Rails.logger.info "[CUSTOMER_LINKER] Successfully merged duplicates into customer #{primary_customer.id}"
    primary_customer
  end
  
  # Sync user data to their linked customer
  def sync_user_data_to_customer(user, customer = nil)
    customer ||= @business.tenant_customers.find_by(user_id: user.id)
    return unless customer
    
    updates = {}
    
    # Sync basic info if customer values are blank
    updates[:first_name] = user.first_name if customer.first_name.blank? && user.first_name.present?
    updates[:last_name] = user.last_name if customer.last_name.blank? && user.last_name.present?
    
    # Sync phone if customer phone is blank and user has phone
    if customer.phone.blank? && user.phone.present?
      updates[:phone] = user.phone
      # Set opt-in if user has opted in
      if user.respond_to?(:phone_opt_in?) && user.phone_opt_in?
        updates[:phone_opt_in] = true
        updates[:phone_opt_in_at] = user.respond_to?(:phone_opt_in_at) ? user.phone_opt_in_at : Time.current
      end
    end
    
    # Sync email if different (but be careful about case)
    if customer.email.downcase != user.email.downcase
      updates[:email] = user.email.downcase.strip
    end
    
    customer.update!(updates) if updates.any?
  end
  
  private
  
  def merge_customer_data(primary, duplicate)
    # Merge non-blank data from duplicate into primary
    updates = {}
    
    # Take non-blank values from duplicate if primary is blank
    %w[first_name last_name phone address].each do |attr|
      if primary.send(attr).blank? && duplicate.send(attr).present?
        updates[attr] = duplicate.send(attr)
      end
    end
    
    # Merge opt-in status (take the more permissive option)
    if !primary.phone_opt_in? && duplicate.phone_opt_in?
      updates[:phone_opt_in] = true
      updates[:phone_opt_in_at] = duplicate.phone_opt_in_at || Time.current
    end
    
    # Take earlier opt-in date if both are opted in
    if primary.phone_opt_in? && duplicate.phone_opt_in? && duplicate.phone_opt_in_at && 
       (primary.phone_opt_in_at.nil? || duplicate.phone_opt_in_at < primary.phone_opt_in_at)
      updates[:phone_opt_in_at] = duplicate.phone_opt_in_at
    end
    
    # Keep the earlier created_at date
    if duplicate.created_at < primary.created_at
      updates[:created_at] = duplicate.created_at
    end
    
    primary.update!(updates) if updates.any?
  end
  
  def move_customer_associations(from_customer, to_customer)
    # Move all bookings
    from_customer.bookings.update_all(tenant_customer_id: to_customer.id)
    
    # Move all orders
    from_customer.orders.update_all(tenant_customer_id: to_customer.id)
    
    # Move all invoices
    from_customer.invoices.update_all(tenant_customer_id: to_customer.id)
    
    # Move all payments
    from_customer.payments.update_all(tenant_customer_id: to_customer.id)
    
    # Move SMS messages
    from_customer.sms_messages.update_all(tenant_customer_id: to_customer.id)
    
    # Move loyalty transactions
    from_customer.loyalty_transactions.update_all(tenant_customer_id: to_customer.id)
    
    # Move loyalty redemptions
    from_customer.loyalty_redemptions.update_all(tenant_customer_id: to_customer.id)
    
    # Move subscription records
    from_customer.customer_subscriptions.update_all(tenant_customer_id: to_customer.id)
    from_customer.subscription_transactions.update_all(tenant_customer_id: to_customer.id)
  end
end
