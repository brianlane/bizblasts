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

    # FIRST: Check for phone duplicates and resolve them automatically
    # This handles cases where multiple customers exist with the same phone number
    phone_duplicates_found = false
    phone_duplicate_resolution_skipped = false
    conflicting_user_id = nil
    if user.phone.present?
      # First, find duplicates without merging to avoid destroying data
      duplicate_customers = find_customers_by_phone(user.phone)
      if duplicate_customers.count > 1
        phone_duplicates_found = true
        # Select canonical customer without merging yet
        canonical_customer = select_canonical_customer(duplicate_customers)

        # Check if canonical customer is already linked to a different user
        if canonical_customer.user_id.present? && canonical_customer.user_id != user.id
          Rails.logger.info "[CUSTOMER_LINKER] Canonical customer #{canonical_customer.id} already linked to user #{canonical_customer.user_id}, skipping phone duplicate resolution for user #{user.id}"
          # Skip duplicate resolution - and skip individual phone linking to prevent data integrity issues
          phone_duplicate_resolution_skipped = true
          conflicting_user_id = canonical_customer.user_id
        elsif canonical_customer.user_id == user.id
          # Already linked to this user, but still merge duplicates for data cleanup
          Rails.logger.info "[CUSTOMER_LINKER] Canonical customer #{canonical_customer.id} already linked to user #{user.id}, merging remaining duplicates"
          merged_canonical = merge_duplicate_customers(duplicate_customers)
          return merged_canonical
        else
          # Canonical customer is unlinked, safe to merge duplicates and link to this user
          Rails.logger.info "[CUSTOMER_LINKER] Auto-resolving phone duplicates for user #{user.id}, using canonical customer #{canonical_customer.id}"
          merged_canonical = merge_duplicate_customers(duplicate_customers)
          merged_canonical.update!(user_id: user.id)
          # Note: Do NOT sync user data here - canonical customer already has the best data (normalized phone, SMS opt-in)
          # Only sync basic info if customer values are blank
          updates = {}
          updates[:first_name] = user.first_name if merged_canonical.first_name.blank? && user.first_name.present?
          updates[:last_name] = user.last_name if merged_canonical.last_name.blank? && user.last_name.present?
          updates[:email] = user.email.downcase.strip if merged_canonical.email.to_s.casecmp?(user.email.to_s) == false
          merged_canonical.update!(updates) if updates.any?
          return merged_canonical
        end
      end
    end

    # SECOND: Check if user already has a linked customer (after duplicate resolution)
    existing_customer = @business.tenant_customers.find_by(user_id: user.id)
    if existing_customer
      # SECURITY: Don't allow linking if phone duplicate resolution was skipped due to conflicts
      if phone_duplicate_resolution_skipped
        Rails.logger.error "[CUSTOMER_LINKER] Cannot link user #{user.id} to existing customer #{existing_customer.id} - phone number conflicts with existing customer accounts (phone sharing not allowed)"
        raise PhoneConflictError.new(
          "This phone number is already associated with another account. Please use a different phone number or contact support if this is your number.",
          phone: user.phone,
          business_id: @business.id,
          existing_user_id: nil, # Unknown which specific user in duplicate scenario
          attempted_user_id: user.id
        )
      end

      # For idempotent calls, only sync basic info (not phone) to preserve data from duplicate resolution
      sync_user_data_to_customer(user, existing_customer, preserve_phone: true)
      return existing_customer
    end

    # THIRD: Look for unlinked customer with same email
    email = user.email.downcase.strip
    unlinked_customer = @business.tenant_customers.find_by(
      email: email,
      user_id: nil
    )

    if unlinked_customer
      # SECURITY: Don't allow linking if phone duplicate resolution was skipped due to conflicts
      if phone_duplicate_resolution_skipped
        Rails.logger.error "[CUSTOMER_LINKER] Cannot link user #{user.id} to unlinked customer #{unlinked_customer.id} - phone number conflicts with existing customer accounts (phone sharing not allowed)"
        raise PhoneConflictError.new(
          "This phone number is already associated with another account. Please use a different phone number or contact support if this is your number.",
          phone: user.phone,
          business_id: @business.id,
          existing_user_id: nil, # Unknown which specific user in duplicate scenario
          attempted_user_id: user.id
        )
      end

      # Link the existing customer to this user
      unlinked_customer.update!(user_id: user.id)
      sync_user_data_to_customer(user, unlinked_customer)
      return unlinked_customer
    end

    # FOURTH: Look for existing customers with same phone number (single customer case)
    # IMPORTANT: Skip this if we found phone duplicates to prevent data integrity issues
    if user.phone.present? && !phone_duplicates_found
      phone_customers = find_customers_by_phone(user.phone)

      # Check if any customer with this phone is linked to a different user (phone uniqueness enforcement)
      linked_to_different_user = phone_customers.find { |c| c.user_id.present? && c.user_id != user.id }
      if linked_to_different_user
        Rails.logger.error "[CUSTOMER_LINKER] Cannot create new customer for user #{user.id} with phone #{user.phone} - phone number already linked to different user #{linked_to_different_user.user_id}"
        raise PhoneConflictError.new(
          "This phone number is already associated with another account. Please use a different phone number or contact support if this is your number.",
          phone: user.phone,
          business_id: @business.id,
          existing_user_id: linked_to_different_user.user_id,
          attempted_user_id: user.id
        )
      end

      # Look for unlinked customer to reuse
      unlinked_phone_customer = phone_customers.find { |c| c.user_id.nil? }
      if unlinked_phone_customer
        Rails.logger.info "[CUSTOMER_LINKER] Linking unlinked customer #{unlinked_phone_customer.id} with matching phone #{user.phone} to user #{user.id}"
        # Link the existing customer to this user
        unlinked_phone_customer.update!(user_id: user.id)
        sync_user_data_to_customer(user, unlinked_phone_customer)
        return unlinked_phone_customer
      end
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

    # IMPORTANT: Don't create new customer if phone duplicate resolution was skipped
    # This prevents data integrity issues where multiple customers have same phone linked to different users
    if phone_duplicate_resolution_skipped
      Rails.logger.error "[CUSTOMER_LINKER] Cannot create new customer for user #{user.id} with phone #{user.phone} - phone number conflicts with existing customer accounts (phone sharing not allowed)"
      raise PhoneConflictError.new(
        "This phone number is already associated with another account. Please use a different phone number or contact support if this is your number.",
        phone: user.phone,
        business_id: @business.id,
        existing_user_id: conflicting_user_id, # ID of user linked to canonical customer
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
      raise GuestConflictError.new(
        "This email address is already associated with an existing account. Please sign in to continue, or use a different email address.",
        email: email,
        business_id: @business.id,
        existing_user_id: linked_customer.user_id
      )
    end

    # Check if phone belongs to an existing linked customer
    if customer_attributes[:phone].present?
      phone_customers = find_customers_by_phone(customer_attributes[:phone])
      linked_phone_customer = phone_customers.find { |c| c.user_id.present? }
      if linked_phone_customer
        raise GuestConflictError.new(
          "This phone number is already associated with an existing account. Please sign in to continue, or use a different phone number.",
          phone: customer_attributes[:phone],
          business_id: @business.id,
          existing_user_id: linked_phone_customer.user_id
        )
      end
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
  def sync_user_data_to_customer(user, customer = nil, preserve_phone: false)
    customer ||= @business.tenant_customers.find_by(user_id: user.id)
    return unless customer

    updates = {}

    # Sync basic info if customer values are blank
    updates[:first_name] = user.first_name if customer.first_name.blank? && user.first_name.present?
    updates[:last_name] = user.last_name if customer.last_name.blank? && user.last_name.present?

    # Sync phone from user to customer - but only if not preserving phone data
    if !preserve_phone && user.phone.present? && customer.phone != user.phone
      updates[:phone] = user.phone
      # IMPORTANT: When phone number changes, sync SMS opt-in status from user for compliance
      # Only update if user has explicit opt-in preferences to avoid overwriting customer's existing consent
      if user.respond_to?(:phone_opt_in?)
        user_opt_in_preference = user.phone_opt_in?

        if user_opt_in_preference == true
          # User has explicit opt-in - sync it (compliance: respect user's consent for new number)
          updates[:phone_opt_in] = true
          updates[:phone_opt_in_at] = user.respond_to?(:phone_opt_in_at) ? user.phone_opt_in_at : Time.current
        elsif user_opt_in_preference == false && customer.phone_opt_in?
          # User explicitly opted out (false, not nil) but customer was opted in - reset for compliance
          # This prevents sending SMS to a number that explicitly opted out
          updates[:phone_opt_in] = false
          updates[:phone_opt_in_at] = nil
        end
        # Note: If user_opt_in_preference is nil (no explicit preference), leave customer opt-in status unchanged
      end
    end

    # Sync email if different (case-insensitive). to_s ensures no nil errors.
    if customer.email.to_s.casecmp?(user.email.to_s) == false
      updates[:email] = user.email.downcase.strip
    end

    customer.update!(updates) if updates.any?
  end

  # Phone number deduplication methods

  # Find or resolve phone number duplicates, returning the canonical customer
  def resolve_phone_duplicates(phone_number)
    return nil if phone_number.blank?

    # Find all customers with any variation of this phone number
    duplicate_customers = find_customers_by_phone(phone_number)

    return nil if duplicate_customers.empty?
    return duplicate_customers.first if duplicate_customers.count == 1

    # Multiple customers found - merge duplicates
    Rails.logger.info "[CUSTOMER_LINKER] Found #{duplicate_customers.count} duplicate customers for phone #{phone_number}"
    merge_duplicate_customers(duplicate_customers)
  end

  # Scan business for phone duplicates and resolve them all
  def resolve_all_phone_duplicates
    duplicates_resolved = 0

    # Group customers by normalized phone number
    phone_groups = @business.tenant_customers
                           .where.not(phone: [nil, ''])
                           .group_by { |customer| normalize_phone(customer.phone) }

    phone_groups.each do |normalized_phone, customers|
      next if customers.count <= 1 # No duplicates

      Rails.logger.info "[CUSTOMER_LINKER] Resolving #{customers.count} duplicates for phone #{normalized_phone}"
      canonical_customer = merge_duplicate_customers(customers)
      duplicates_resolved += customers.count - 1 if canonical_customer
    end

    Rails.logger.info "[CUSTOMER_LINKER] Resolved #{duplicates_resolved} duplicate customers for business #{@business.id}"
    duplicates_resolved
  end

  # Public interface for external classes to find customers by phone
  # This allows other classes like TwilioController to reuse the phone lookup logic
  def find_customers_by_phone_public(phone_number)
    find_customers_by_phone(phone_number)
  end

  # Class method for external use - allows global or business-scoped phone lookup
  # WARNING: When business is nil, this performs a GLOBAL lookup across ALL businesses
  # Only use global lookups for legitimate cross-business scenarios (e.g., SMS webhooks)
  # Reuses the phone normalization and format generation logic
  def self.find_customers_by_phone_global(phone_number, business = nil)
    # Generate all possible phone number formats (same logic as instance method)
    normalized = self.normalize_phone_static(phone_number)
    digits_only = phone_number.gsub(/\D/, '')
    without_country = digits_only.length == 11 ? digits_only[1..-1] : digits_only

    possible_formats = [
      normalized,           # +16026866672
      digits_only,         # 16026866672 or 6026866672
      without_country,     # 6026866672
      "1#{without_country}" # 16026866672
    ].uniq.compact

    # Build query - global or business-scoped
    # When business is nil/blank, this intentionally searches across ALL businesses
    # This is typically only appropriate for webhook processing where business context is unknown
    query = TenantCustomer.where(phone: possible_formats)
    query = query.where(business: business) if business.present?

    # Log global lookups for security auditing
    if business.blank?
      Rails.logger.info "[SECURITY] Global customer lookup performed for phone #{phone_number} - ensure this is intentional"
    end

    query
  end

  # Safer alternative that requires explicit intent for global lookups
  # Use this when you specifically need to search across all businesses
  def self.find_customers_by_phone_across_all_businesses(phone_number)
    Rails.logger.info "[SECURITY] Intentional global customer lookup for phone #{phone_number}"
    find_customers_by_phone_global(phone_number, nil)
  end

  # Static version of phone normalization for class method use
  def self.normalize_phone_static(phone)
    return nil if phone.blank?
    cleaned = phone.gsub(/\D/, '')
    cleaned = "1#{cleaned}" if cleaned.length == 10
    "+#{cleaned}"
  end

  protected

  # Robust phone lookup that handles multiple formats in database
  def find_customers_by_phone(phone_number)
    # Generate all possible phone number formats that might be stored
    normalized = normalize_phone(phone_number)
    digits_only = phone_number.gsub(/\D/, '')
    without_country = digits_only.length == 11 ? digits_only[1..-1] : digits_only

    possible_formats = [
      normalized,           # +16026866672
      digits_only,         # 16026866672 or 6026866672
      without_country,     # 6026866672
      "1#{without_country}" # 16026866672
    ].uniq.compact

    @business.tenant_customers.where(phone: possible_formats)
  end

  private

  # Phone number normalization (consistent with TwilioController)
  def normalize_phone(phone)
    return nil if phone.blank?
    cleaned = phone.gsub(/\D/, '')
    cleaned = "1#{cleaned}" if cleaned.length == 10
    "+#{cleaned}"
  end

  # Merge duplicate customers, selecting the most authoritative as canonical
  def merge_duplicate_customers(customers)
    # Select canonical customer (prioritize linked users, then completeness, then age)
    canonical_customer = select_canonical_customer(customers)
    duplicate_customers = customers - [canonical_customer]

    Rails.logger.info "[CUSTOMER_LINKER] Using customer #{canonical_customer.id} as canonical, merging #{duplicate_customers.count} duplicates"

    # Merge data from duplicates into canonical customer
    merge_customer_data(canonical_customer, duplicate_customers)

    # Update all related records to point to canonical customer
    migrate_customer_relationships(canonical_customer, duplicate_customers)

    # Normalize phone number format
    if canonical_customer.phone.present?
      canonical_customer.update_column(:phone, normalize_phone(canonical_customer.phone))
    end

    # Delete duplicate customers
    duplicate_customers.each do |duplicate|
      Rails.logger.info "[CUSTOMER_LINKER] Deleting duplicate customer #{duplicate.id}"
      duplicate.destroy!
    end

    canonical_customer
  end

  def select_canonical_customer(customers)
    # Priority order for canonical customer:
    # 1. Customer linked to User account (most authoritative)
    # 2. Customer with real email (not temp/SMS-generated)
    # 3. Customer with most complete data
    # 4. Oldest customer

    customers.sort_by do |customer|
      [
        customer.user_id ? 0 : 1,                    # User-linked first
        customer.email&.include?('@temp.') ? 1 : 0,  # Real email over temp
        -customer_completeness_score(customer),       # Most complete data
        customer.created_at                          # Oldest first
      ]
    end.first
  end

  def customer_completeness_score(customer)
    score = 0
    score += 1 if customer.first_name.present?
    score += 1 if customer.last_name.present?
    score += 1 if customer.email.present? && !customer.email.include?('@temp.')
    score += 1 if customer.phone.present?
    score += 1 if customer.phone_opt_in?
    score
  end

  def merge_customer_data(canonical, duplicates)
    updates = {}

    duplicates.each do |duplicate|
      # Merge missing data from duplicates
      updates[:first_name] = duplicate.first_name if canonical.first_name.blank? && duplicate.first_name.present?
      updates[:last_name] = duplicate.last_name if canonical.last_name.blank? && duplicate.last_name.present?

      # Use real email over temp email
      if canonical.email.include?('@temp.') && duplicate.email.present? && !duplicate.email.include?('@temp.')
        updates[:email] = duplicate.email
      end

      # Preserve SMS opt-in if any duplicate has it
      if !canonical.phone_opt_in? && duplicate.phone_opt_in?
        updates[:phone_opt_in] = true
        updates[:phone_opt_in_at] = duplicate.phone_opt_in_at || Time.current
      end
    end

    canonical.update!(updates) if updates.any?
  end

  def migrate_customer_relationships(canonical, duplicates)
    duplicate_ids = duplicates.map(&:id)

    # Update relationships to point to canonical customer
    models_to_update = [
      { model: Booking, foreign_key: :tenant_customer_id },
      { model: Order, foreign_key: :tenant_customer_id },
      { model: SmsMessage, foreign_key: :tenant_customer_id },
      { model: SmsOptInInvitation, foreign_key: :tenant_customer_id }
    ]

    models_to_update.each do |config|
      model = config[:model]
      foreign_key = config[:foreign_key]

      next unless defined?(model)

      updated_count = model.where(foreign_key => duplicate_ids)
                           .update_all(foreign_key => canonical.id)

      Rails.logger.info "[CUSTOMER_LINKER] Updated #{updated_count} #{model.name} records to canonical customer #{canonical.id}" if updated_count > 0
    end
  end

end
