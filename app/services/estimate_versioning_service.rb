# frozen_string_literal: true

# Service for managing estimate version history
# Creates snapshots of estimates when they are updated after being sent to customers
# Allows restoration to previous versions if needed
class EstimateVersioningService
  attr_reader :estimate

  def initialize(estimate)
    @estimate = estimate
  end

  # Create a new version snapshot of the current estimate state
  # Only creates versions for estimates that have been sent to customers
  # Returns the created EstimateVersion or nil if not applicable
  def self.create_version(estimate, change_notes: nil)
    new(estimate).create_version(change_notes: change_notes)
  end

  def create_version(change_notes: nil)
    # Only version estimates that have been sent
    return nil unless estimate.sent? || estimate.viewed? || estimate.pending_payment?

    # Don't version if no meaningful changes occurred
    return nil unless should_create_version?

    # Increment version number
    next_version = estimate.total_versions + 1

    # Create version snapshot
    version = estimate.estimate_versions.create!(
      version_number: next_version,
      snapshot: create_snapshot,
      change_notes: change_notes || generate_change_notes
    )

    # Update estimate version tracking
    estimate.update_columns(
      current_version: next_version,
      total_versions: next_version
    )

    # Send update notification to customer
    EstimateMailer.estimate_updated(estimate).deliver_later

    version
  end

  # Restore estimate to a previous version
  # Returns true if successful, false otherwise
  def self.restore_version(estimate_version)
    new(estimate_version.estimate).restore_version(estimate_version)
  end

  def restore_version(estimate_version)
    return false unless estimate_version.is_a?(EstimateVersion)
    return false if estimate_version.estimate != estimate

    snapshot = estimate_version.snapshot
    estimate_data = snapshot['estimate'] || {}
    items_data = snapshot['items'] || []

    ActiveRecord::Base.transaction do
      # Restore estimate attributes (excluding timestamps and versioning fields)
      restorable_attrs = estimate_data.except(
        'id', 'created_at', 'updated_at', 'business_id',
        'current_version', 'total_versions', 'token', 'estimate_number'
      )

      estimate.assign_attributes(restorable_attrs)

      # Delete current estimate items
      estimate.estimate_items.destroy_all

      # Recreate items from snapshot
      items_data.each do |item_data|
        item_attrs = item_data.except('id', 'estimate_id', 'created_at', 'updated_at')
        estimate.estimate_items.build(item_attrs)
      end

      # Save estimate without triggering callbacks (skip_callbacks: true would be ideal, but we'll use update_columns)
      # First save the items
      estimate.estimate_items.each { |item| item.save!(validate: false) }

      # Recalculate totals (calculate_totals is private, so use send)
      estimate.send(:calculate_totals)

      # Update estimate attributes without triggering callbacks
      estimate.update_columns(estimate.attributes.slice(
        'subtotal', 'taxes', 'total', 'has_optional_items',
        'optional_items_subtotal', 'optional_items_taxes',
        'required_deposit', 'deposit_percentage', 'status'
      ))

      # Create a new version noting the restoration
      estimate.estimate_versions.create!(
        version_number: estimate.total_versions + 1,
        snapshot: create_snapshot,
        change_notes: "Restored to version #{estimate_version.version_number}"
      )

      estimate.update_columns(
        current_version: estimate.total_versions + 1,
        total_versions: estimate.total_versions + 1
      )
    end

    true
  rescue => e
    Rails.logger.error("Failed to restore estimate version: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    false
  end

  private

  # Determine if a version should be created
  # Only create if there are actual changes to items or totals
  # Note: When called from after_update callback, estimate.changes will be empty
  # The Estimate model's should_version? method handles the change detection
  def should_create_version?
    # Always create version if this is the first one
    return true if estimate.total_versions == 0

    # When called from after_update callback, check previous_changes instead of changes
    # previous_changes contains the changes from the last save
    changes_hash = estimate.changed? ? estimate.changes : estimate.previous_changes

    # Return false if no changes at all
    return false if changes_hash.blank?

    # Version if any of these key fields changed
    versioned_fields = %w[subtotal taxes total has_optional_items
                           optional_items_subtotal optional_items_taxes
                           required_deposit deposit_percentage]

    # Check for meaningful changes
    versioned_fields.any? { |field| changes_hash.key?(field) }
  end

  # Create a complete snapshot of the estimate and its items
  def create_snapshot
    {
      'created_at' => Time.current.iso8601,
      'estimate' => estimate.attributes,
      'items' => estimate.estimate_items.map(&:attributes),
      'customer' => customer_snapshot,
      'version_metadata' => {
        'total' => estimate.total,
        'subtotal' => estimate.subtotal,
        'taxes' => estimate.taxes,
        'item_count' => estimate.estimate_items.count,
        'optional_item_count' => estimate.estimate_items.where(optional: true).count,
        'has_signature' => estimate.signed?
      }
    }
  end

  # Create snapshot of customer data
  def customer_snapshot
    if estimate.tenant_customer.present?
      {
        'id' => estimate.tenant_customer.id,
        'name' => estimate.customer_full_name,
        'email' => estimate.customer_email,
        'phone' => estimate.customer_phone
      }
    else
      {
        'name' => estimate.customer_full_name,
        'email' => estimate.customer_email,
        'phone' => estimate.customer_phone,
        'address' => estimate.full_address
      }
    end
  end

  # Generate automatic change notes based on what changed
  def generate_change_notes
    changes = []

    # Use previous_changes when called from callback, changes otherwise
    changes_hash = estimate.changed? ? estimate.changes : estimate.previous_changes

    # Check total change
    if changes_hash['total']
      old_total = changes_hash['total'][0].to_f
      new_total = changes_hash['total'][1].to_f
      diff = new_total - old_total
      changes << "Total #{diff >= 0 ? 'increased' : 'decreased'} by #{ActionController::Base.helpers.number_to_currency(diff.abs)}"
    end

    # Check item count changes
    changes << "Items updated" if changes_hash.keys.any? { |k| k.start_with?('estimate_items') }

    # Check optional items
    if changes_hash['has_optional_items']
      changes << (estimate.has_optional_items? ? "Optional items added" : "Optional items removed")
    end

    # Default message if no specific changes detected
    return "Estimate updated" if changes.empty?

    changes.join(', ')
  end
end
