# frozen_string_literal: true

# Service for merging duplicate customer records
# Extracted from CustomerLinker to reduce complexity and improve maintainability
class CustomerMerger
  # Merge duplicate customers, selecting the most authoritative as canonical
  def self.merge_duplicate_customers(customers, business:, phone_normalizer:)
    # Select canonical customer (prioritize linked users, then completeness, then age)
    canonical_customer = select_canonical_customer(customers)
    duplicate_customers = customers - [canonical_customer]

    Rails.logger.info "[CUSTOMER_MERGER] Using customer #{canonical_customer.id} as canonical, merging #{duplicate_customers.count} duplicates"

    # Merge data from duplicates into canonical customer
    merge_customer_data(canonical_customer, duplicate_customers)

    # Update all related records to point to canonical customer
    migrate_customer_relationships(canonical_customer, duplicate_customers)

    # Normalize phone number format
    if canonical_customer.phone.present?
      normalized_phone = phone_normalizer.call(canonical_customer.phone)
      # Only update if normalization succeeded to preserve original data for invalid phone numbers
      canonical_customer.update_column(:phone, normalized_phone) if normalized_phone.present?
    end

    # Delete duplicate customers
    duplicate_customers.each do |duplicate|
      Rails.logger.info "[CUSTOMER_MERGER] Deleting duplicate customer #{duplicate.id}"
      duplicate.destroy!
    end

    canonical_customer
  end

  def self.select_canonical_customer(customers)
    # Priority order for canonical customer:
    # 1. Customer linked to User account (most authoritative)
    # 2. Customer with real email (not temp/SMS-generated)
    # 3. Customer with most complete data
    # 4. Oldest customer

    customers.sort_by do |customer|
      [
        customer.user_id ? 0 : 1,                    # User-linked first
        customer.email&.include?('@temp.') || customer.email&.include?('@invalid.example') ? 1 : 0,  # Real email over temp
        -customer_completeness_score(customer),       # Most complete data
        customer.created_at                          # Oldest first
      ]
    end.first
  end

  def self.customer_completeness_score(customer)
    score = 0
    score += 1 if customer.first_name.present?
    score += 1 if customer.last_name.present?
    score += 1 if customer.email.present? && !customer.email.include?('@temp.') && !customer.email.include?('@invalid.example')
    score += 1 if customer.phone.present?
    score += 1 if customer.phone_opt_in?
    score
  end

  def self.merge_customer_data(canonical, duplicates)
    updates = {}

    duplicates.each do |duplicate|
      # Merge missing data from duplicates
      updates[:first_name] = duplicate.first_name if canonical.first_name.blank? && duplicate.first_name.present?
      updates[:last_name] = duplicate.last_name if canonical.last_name.blank? && duplicate.last_name.present?

      # Use real email over temp email
      if (canonical.email.include?('@temp.') || canonical.email.include?('@invalid.example')) &&
         duplicate.email.present? &&
         !duplicate.email.include?('@temp.') &&
         !duplicate.email.include?('@invalid.example')
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

  def self.migrate_customer_relationships(canonical, duplicates)
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

      Rails.logger.info "[CUSTOMER_MERGER] Updated #{updated_count} #{model.name} records to canonical customer #{canonical.id}" if updated_count > 0
    end
  end
end
