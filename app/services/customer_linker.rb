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

    # Step 1: Resolve phone conflicts and duplicates
    phone_conflict_result = resolve_phone_conflicts_for_user(user)
    return phone_conflict_result[:customer] if phone_conflict_result[:customer]

    # Step 2: Handle existing linked customer
    existing_customer = handle_existing_customer_for_user(user, phone_conflict_result)
    return existing_customer if existing_customer

    # Step 3: Handle unlinked customer with same email
    unlinked_customer = handle_unlinked_customer_by_email(user, phone_conflict_result)
    return unlinked_customer if unlinked_customer

    # Step 4: Handle customers with same phone number (single customer case)
    phone_customer = handle_unlinked_customer_by_phone(user, phone_conflict_result)
    return phone_customer if phone_customer

    # Step 5: Check for email conflicts
    check_email_conflicts(user)

    # Step 6: Final phone conflict check before creation
    check_final_phone_conflicts(user, phone_conflict_result)

    # Step 7: Create new customer
    create_new_customer_for_user(user, customer_attributes)
  end

  # Find or create customer for guest checkout (no user account)
  #
  # Returns the guest customer if found or created successfully.
  #
  # @raise [GuestConflictError] if the email or phone is already linked to a registered user account
  #   This security check prevents guests from using credentials belonging to registered users.
  #   Callers should handle this exception and prompt the user to sign in instead.
  #
  # @param email [String] The email address for the guest customer
  # @param customer_attributes [Hash] Additional attributes (first_name, last_name, phone, phone_opt_in)
  # @return [TenantCustomer] The guest customer record
  def find_or_create_guest_customer(email, customer_attributes = {})
    email = email.downcase.strip
    
    customer = @business.tenant_customers.find_by(email: email, user_id: nil)
    if customer
      # Update existing guest customer with any new attributes provided
      updates = {}
      %i[first_name last_name].each do |attr|
        value = customer_attributes[attr]
        updates[attr] = value if value.present? && customer.send(attr) != value
      end

      # Handle phone updates with validation (Bug 11 fix)
      if customer_attributes[:phone].present?
        phone_value = customer_attributes[:phone]
        normalized_phone = normalize_phone(phone_value)

        if normalized_phone.present?
          # Valid phone - update if different
          updates[:phone] = phone_value if customer.phone != phone_value
        else
          # Invalid phone - clear it and log warning (Bug 11 fix)
          Rails.logger.warn "[CUSTOMER_LINKER] Invalid phone number provided for guest customer update (too short or invalid format), clearing phone field: #{phone_value}"
          updates[:phone] = nil if customer.phone.present? # Only clear if customer currently has a phone
        end
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
        business_id: @business.safe_identifier_for_logging,
        existing_user_id: linked_customer.user_id
      )
    end

    # Check if phone belongs to an existing linked customer
    # IMPORTANT: Validate phone is actually valid before querying (Bug 7 fix)
    # This prevents unnecessary database queries for blank/invalid phone numbers
    if customer_attributes[:phone].present?
      normalized_phone = normalize_phone(customer_attributes[:phone])

      # Only check for conflicts if phone is valid (normalize_phone returns non-nil)
      # Invalid phones (< 7 digits) will be nil and skip this check
      if normalized_phone.present?
        # Use the already-normalized phone for consistency (Bug 9 fix)
        # This avoids redundant normalization and ensures we're checking with the exact normalized value
        phone_customers = find_customers_by_phone(normalized_phone)
        # Use ActiveRecord to filter in SQL instead of loading all customers and filtering in Ruby
        linked_phone_customer = phone_customers.where.not(user_id: nil).first
        if linked_phone_customer
          raise GuestConflictError.new(
            "This phone number is already associated with an existing account. Please sign in to continue, or use a different phone number.",
            phone: customer_attributes[:phone],
            business_id: @business.safe_identifier_for_logging,
            existing_user_id: linked_phone_customer.user_id
          )
        end
      else
        # Bug 11 fix: If phone is invalid (normalization returned nil), don't store it
        # This prevents storing garbage data and prevents duplicate accounts with same invalid phone
        # Remove invalid phone from attributes before storing
        Rails.logger.warn "[CUSTOMER_LINKER] Invalid phone number provided for guest customer (too short or invalid format), clearing phone field: #{customer_attributes[:phone]}"
        customer_attributes.delete(:phone)
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

    # Process customers in batches to avoid memory overload for large datasets
    # Database-portable approach: filter valid phones in Ruby after loading
    phone_groups = {}

    @business.tenant_customers
             .where.not(phone: [nil, ''])
             .find_in_batches(batch_size: 1000) do |batch|

      # Group this batch by normalized phone
      # Ruby-level normalization handles validity checks (length >= 7) for database portability
      batch_groups = batch.group_by { |customer|
        normalized = normalize_phone(customer.phone)
        normalized.presence # Skip customers where normalization fails (nil for invalid phones)
      }.reject { |normalized_phone, customers| normalized_phone.nil? }

      # Merge batch groups into main phone_groups hash
      batch_groups.each do |normalized_phone, customers|
        phone_groups[normalized_phone] ||= []
        phone_groups[normalized_phone].concat(customers)
      end
    end

    phone_groups.each do |normalized_phone, customers|
      next if customers.count <= 1 # No duplicates

      Rails.logger.info "[CUSTOMER_LINKER] Resolving #{customers.count} duplicates for phone #{normalized_phone}"
      canonical_customer = merge_duplicate_customers(customers)
      duplicates_resolved += customers.count - 1 if canonical_customer
    end

    Rails.logger.info "[CUSTOMER_LINKER] Resolved #{duplicates_resolved} duplicate customers for business #{@business.safe_identifier_for_logging}"
    duplicates_resolved
  end

  # Instance method: Find customers by phone within the business scope set during initialization
  #
  # Use this when you have a CustomerLinker instance already (e.g., in tests or internal methods)
  # Returns Array for consistent behavior with webhook processing
  #
  # @param phone_number [String] The phone number to search for
  # @return [Array<TenantCustomer>] Customers matching the phone number in this business
  # @note This method is scoped to @business. For external callers, prefer the class method.
  # @see .find_customers_by_phone_public for the class method version
  def find_customers_by_phone_public(phone_number)
    find_customers_by_phone(phone_number).to_a
  end

  # Class method for external use - allows global or business-scoped phone lookup
  # WARNING: When business is nil, this performs a GLOBAL lookup across ALL businesses
  # Only use global lookups for legitimate cross-business scenarios (e.g., SMS webhooks)
  # Reuses the phone normalization and format generation logic
  def self.find_customers_by_phone_global(phone_number, business = nil)
    # Generate all possible phone number formats consistently from normalized input
    normalized = self.normalize_phone_static(phone_number)
    # Return empty array for blank input to maintain consistency with instance method
    # This ensures downstream methods like select_canonical_customer work consistently
    return [] if normalized.blank?

    # Derive all format variations from the normalized phone number for consistency
    digits_only = normalized.gsub(/\D/, '')
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

    # Return Array for consistent type with instance method
    query.to_a
  end

  # Safer alternative that requires explicit intent for global lookups
  # Use this when you specifically need to search across all businesses
  def self.find_customers_by_phone_across_all_businesses(phone_number)
    Rails.logger.info "[SECURITY] Intentional global customer lookup for phone #{phone_number}"
    find_customers_by_phone_global(phone_number, nil)
  end

  # Class method: Find customers by phone for a specific business (preferred for external callers)
  #
  # Use this when calling from controllers or other services without a CustomerLinker instance.
  # This is the RECOMMENDED method for external callers.
  #
  # @param phone_number [String] The phone number to search for
  # @param business [Business] The business to scope the search to
  # @return [Array<TenantCustomer>] Customers matching the phone number in the specified business
  # @note This is the class method version. There is also an instance method with the same name
  #   but different arity (1 parameter vs 2). Use this class method for external calls.
  # @see #find_customers_by_phone_public for the instance method version
  # @example
  #   CustomerLinker.find_customers_by_phone_public('+16026866672', current_business)
  def self.find_customers_by_phone_public(phone_number, business)
    find_customers_by_phone_global(phone_number, business)
  end

  # Static version of phone normalization for class method use
  def self.normalize_phone_static(phone)
    return nil if phone.blank?
    cleaned = phone.gsub(/\D/, '')
    # Treat phone numbers with fewer than 7 digits as invalid (too short to be real phone numbers)
    return nil if cleaned.length < 7
    cleaned = "1#{cleaned}" if cleaned.length == 10
    "+#{cleaned}"
  end

  protected

  # Robust phone lookup that handles multiple formats in database
  # Returns ActiveRecord::Relation for consistent chaining in internal CustomerLinker methods
  def find_customers_by_phone(phone_number)
    # Generate all possible phone number formats consistently from normalized input
    normalized = normalize_phone(phone_number)
    # Return empty relation for blank input to maintain ActiveRecord::Relation type consistency
    # This ensures downstream methods like select_canonical_customer work consistently
    return @business.tenant_customers.none if normalized.blank?

    # Derive all format variations from the normalized phone number for consistency
    digits_only = normalized.gsub(/\D/, '')
    without_country = digits_only.length == 11 ? digits_only[1..-1] : digits_only

    possible_formats = [
      normalized,           # +16026866672
      digits_only,         # 16026866672 or 6026866672
      without_country,     # 6026866672
      "1#{without_country}" # 16026866672
    ].uniq.compact

    @business.tenant_customers.where(phone: possible_formats)
  end

  # Phone number normalization (consistent with TwilioController)
  # Moved to protected to allow access from other protected methods
  def normalize_phone(phone)
    return nil if phone.blank?
    cleaned = phone.gsub(/\D/, '')
    # Treat phone numbers with fewer than 7 digits as invalid (too short to be real phone numbers)
    return nil if cleaned.length < 7
    cleaned = "1#{cleaned}" if cleaned.length == 10
    "+#{cleaned}"
  end

  private

  # Extracted methods from link_user_to_customer refactor

  # Step 1: Resolve phone conflicts and duplicates
  # Uses CustomerConflictResolver and CustomerMerger for cleaner separation of concerns
  def resolve_phone_conflicts_for_user(user)
    conflict_resolver = CustomerConflictResolver.new(@business)
    result = conflict_resolver.resolve_phone_conflicts_for_user(user, customer_finder: self)

    # Handle scenarios where merging and linking should happen
    if result[:duplicate_customers] && result[:canonical_customer]
      canonical = result[:canonical_customer]
      duplicates = result[:duplicate_customers]

      # IMPORTANT FIX: Merge duplicates first for data integrity, regardless of the linking outcome.
      # This addresses the failing test case where duplicates must be consolidated even if a
      # conflict prevents linking.
      merged_canonical = merge_duplicate_customers(duplicates)

      if canonical.user_id == user.id
        # Already linked to this user, return the merged canonical customer
        return { customer: merged_canonical }
      elsif canonical.user_id.nil?
        # Canonical customer is unlinked, link to user and update fields

        # IMPORTANT (Bug 10 fix): Combine user_id and other updates into single atomic operation
        updates = { user_id: user.id }
        updates[:first_name] = user.first_name if merged_canonical.first_name.blank? && user.first_name.present?
        updates[:last_name] = user.last_name if merged_canonical.last_name.blank? && user.last_name.present?
        updates[:email] = user.email.downcase.strip if merged_canonical.email.to_s.casecmp?(user.email.to_s) == false

        merged_canonical.update!(updates)
        return { customer: merged_canonical }
      else
        # Canonical already linked to different user. Merge happened above.
        # Now, return the conflict flag/result for the subsequent steps to raise the error,
        # but the essential merge is now complete.
        Rails.logger.info "[CUSTOMER_LINKER] Phone conflict found: canonical customer #{canonical.id} linked to different user #{canonical.user_id}. Merge performed."
      end
    end

    # Return original result (now without :canonical_customer and :duplicate_customers, but possibly with conflict flags)
    # The conflict flags will be used in later steps (Step 6) to raise the final error,
    # but the essential merge is now complete.
    result.except(:canonical_customer, :duplicate_customers)
  end

  # Step 2: Handle existing linked customer
  def handle_existing_customer_for_user(user, phone_conflict_result)
    existing_customer = @business.tenant_customers.find_by(user_id: user.id)
    return nil unless existing_customer

    # User should always be able to access their own existing customer account
    # Phone conflicts only prevent NEW linkages, not accessing existing ones
    Rails.logger.info "[CUSTOMER_LINKER] User #{user.id} accessing existing linked customer #{existing_customer.id}"

    # For idempotent calls, only sync basic info (not phone) to preserve data from duplicate resolution
    sync_user_data_to_customer(user, existing_customer, preserve_phone: true)
    existing_customer
  end

  # Step 3: Handle unlinked customer with same email
  def handle_unlinked_customer_by_email(user, phone_conflict_result)
    email = user.email.downcase.strip
    unlinked_customer = @business.tenant_customers.find_by(
      email: email,
      user_id: nil
    )

    return nil unless unlinked_customer

    # SECURITY: Don't allow linking if phone duplicate resolution was skipped due to conflicts
    # Uses CustomerConflictResolver for consistent error handling
    conflict_resolver = CustomerConflictResolver.new(@business)
    conflict_resolver.check_phone_conflict_prevents_linking(user, phone_conflict_result)

    # Link the existing customer to this user
    unlinked_customer.update!(user_id: user.id)
    sync_user_data_to_customer(user, unlinked_customer)
    unlinked_customer
  end

  # Step 4: Handle customers with same phone number (single customer case)
  def handle_unlinked_customer_by_phone(user, phone_conflict_result)
    # IMPORTANT: Skip this if we found phone duplicates to prevent data integrity issues
    return nil unless user.phone.present? && !phone_conflict_result[:phone_duplicates_found]

    phone_customers = find_customers_by_phone(user.phone)

    # Check if any customer with this phone is linked to a different user (phone uniqueness enforcement)
    # Uses CustomerConflictResolver for consistent error handling
    conflict_resolver = CustomerConflictResolver.new(@business)
    conflict_resolver.check_phone_uniqueness(phone_customers, user)

    # Look for unlinked customer to reuse
    unlinked_phone_customer = phone_customers.find { |c| c.user_id.nil? }
    if unlinked_phone_customer
      Rails.logger.info "[CUSTOMER_LINKER] Linking unlinked customer #{unlinked_phone_customer.id} with matching phone #{user.phone} to user #{user.id}"
      # Link the existing customer to this user
      unlinked_phone_customer.update!(user_id: user.id)
      sync_user_data_to_customer(user, unlinked_phone_customer)
      return unlinked_phone_customer
    end

    nil
  end

  # Step 5: Check for email conflicts
  def check_email_conflicts(user)
    conflict_resolver = CustomerConflictResolver.new(@business)
    conflict_resolver.check_email_conflict(user)
  end

  # Step 6: Final phone conflict check before creation
  def check_final_phone_conflicts(user, phone_conflict_result)
    conflict_resolver = CustomerConflictResolver.new(@business)
    conflict_resolver.check_phone_conflict_prevents_linking(user, phone_conflict_result)
  end

  # Step 7: Create new customer
  def create_new_customer_for_user(user, customer_attributes)
    email = user.email.downcase.strip
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

  # Merge duplicate customers using CustomerMerger service
  # Delegated to CustomerMerger for cleaner separation of concerns
  def merge_duplicate_customers(customers)
    CustomerMerger.merge_duplicate_customers(
      customers,
      business: @business,
      phone_normalizer: method(:normalize_phone)
    )
  end

  # Backward compatibility wrappers for tests
  # These delegate to CustomerMerger but maintain the same interface
  def select_canonical_customer(customers)
    CustomerMerger.select_canonical_customer(customers)
  end

  def customer_completeness_score(customer)
    CustomerMerger.customer_completeness_score(customer)
  end

  def merge_customer_data(canonical, duplicates)
    CustomerMerger.merge_customer_data(canonical, duplicates)
  end

  def migrate_customer_relationships(canonical, duplicates)
    CustomerMerger.migrate_customer_relationships(canonical, duplicates)
  end

end
