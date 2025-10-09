# frozen_string_literal: true

# Service for detecting and resolving customer conflicts (phone/email)
# Extracted from CustomerLinker to reduce complexity and improve maintainability
class CustomerConflictResolver
  def initialize(business)
    @business = business
  end


  # Check for phone conflicts when linking a user
  # Returns hash with conflict information
  def resolve_phone_conflicts_for_user(user, customer_finder:)
    phone_duplicates_found = false
    phone_duplicate_resolution_skipped = false
    conflicting_user_id = nil

    if user.phone.present?
      # First, find duplicates without merging to avoid destroying data
      # Use send to access protected method
      duplicate_customers = customer_finder.send(:find_customers_by_phone, user.phone)
      if duplicate_customers.count > 1
        phone_duplicates_found = true
        # Select canonical customer without merging yet
        canonical_customer = CustomerMerger.select_canonical_customer(duplicate_customers)

        # Check if canonical customer is already linked to a different user
        if canonical_customer.user_id.present? && canonical_customer.user_id != user.id
          Rails.logger.info "[CONFLICT_RESOLVER] Canonical customer #{canonical_customer.id} already linked to user #{canonical_customer.user_id}, conflict detected"
          # CRITICAL: Set phone_duplicate_resolution_skipped to prevent linking/creating customers with conflicting phones
          phone_duplicate_resolution_skipped = true
          conflicting_user_id = canonical_customer.user_id
        elsif canonical_customer.user_id == user.id
          # Already linked to this user
          Rails.logger.info "[CONFLICT_RESOLVER] Canonical customer #{canonical_customer.id} already linked to user #{user.id}"
          return {
            phone_duplicates_found: phone_duplicates_found,
            phone_duplicate_resolution_skipped: phone_duplicate_resolution_skipped,
            conflicting_user_id: conflicting_user_id,
            canonical_customer: canonical_customer,
            duplicate_customers: duplicate_customers
          }
        else
          # Canonical customer is unlinked, safe to merge
          Rails.logger.info "[CONFLICT_RESOLVER] Canonical customer #{canonical_customer.id} is unlinked, can proceed with merge and link"
          return {
            phone_duplicates_found: phone_duplicates_found,
            phone_duplicate_resolution_skipped: phone_duplicate_resolution_skipped,
            conflicting_user_id: conflicting_user_id,
            canonical_customer: canonical_customer,
            duplicate_customers: duplicate_customers
          }
        end
      end
    end

    {
      phone_duplicates_found: phone_duplicates_found,
      phone_duplicate_resolution_skipped: phone_duplicate_resolution_skipped,
      conflicting_user_id: conflicting_user_id
    }
  end

  # Check if email conflicts exist
  def check_email_conflict(user)
    email = user.email.downcase.strip
    existing_customer = @business.tenant_customers.find_by(email: email)
    if existing_customer&.user_id && existing_customer.user_id != user.id
      Rails.logger.error "[CONFLICT_RESOLVER] Email conflict: #{email} already linked to different user #{existing_customer.user_id}"

      raise EmailConflictError.new(
        "Email #{email} is already associated with a different customer account in this business. Please contact support for assistance.",
        email: email,
        business_id: @business.safe_identifier_for_logging,
        existing_user_id: existing_customer.user_id,
        attempted_user_id: user.id
      )
    end
  end

  # Check if user should be prevented from linking due to phone conflicts
  def check_phone_conflict_prevents_linking(user, phone_conflict_result)
    if phone_conflict_result[:phone_duplicate_resolution_skipped]
      Rails.logger.error "[CONFLICT_RESOLVER] Cannot link user #{user.id} - phone conflicts with existing account"
      raise PhoneConflictError.new(
        "This phone number is already associated with another account. Please use a different phone number or contact support if this is your number.",
        phone: user.phone,
        business_id: @business.safe_identifier_for_logging,
        existing_user_id: phone_conflict_result[:conflicting_user_id],
        attempted_user_id: user.id
      )
    end
  end

  # Check if phone is already linked to a different user (single customer case)
  def check_phone_uniqueness(phone_customers, user)
    linked_to_different_user = phone_customers.find { |c| c.user_id.present? && c.user_id != user.id }
    if linked_to_different_user
      Rails.logger.error "[CONFLICT_RESOLVER] Phone #{user.phone} already linked to different user #{linked_to_different_user.user_id}"
      raise PhoneConflictError.new(
        "This phone number is already associated with another account. Please use a different phone number or contact support if this is your number.",
        phone: user.phone,
        business_id: @business.safe_identifier_for_logging,
        existing_user_id: linked_to_different_user.user_id,
        attempted_user_id: user.id
      )
    end
  end
end
