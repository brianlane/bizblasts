# frozen_string_literal: true

namespace :estimates do
  desc 'Migrate existing estimates to enhanced schema'
  task migrate_to_enhanced_schema: :environment do
    puts "=" * 80
    puts "Starting Estimate Migration to Enhanced Schema"
    puts "=" * 80
    puts

    # Count totals
    total_estimates = Estimate.count
    total_items = EstimateItem.count

    puts "Found #{total_estimates} estimates and #{total_items} estimate items to process"
    puts

    migrated_estimates = 0
    migrated_items = 0
    errors = []

    # Process each business separately for proper tenant scoping
    Business.find_each do |business|
      ActsAsTenant.with_tenant(business) do
        business_estimates = business.estimates

        next if business_estimates.none?

        puts "Processing business: #{business.name} (#{business_estimates.count} estimates)"

        business_estimates.find_each do |estimate|
          begin
            updated = false

            # 1. Generate estimate_number if missing
            if estimate.estimate_number.blank?
              # Temporarily bypass validation to set estimate_number
              estimate.update_column(:estimate_number, generate_estimate_number_for(estimate, business))
              puts "  ✓ Generated estimate number: #{estimate.estimate_number}"
              updated = true
            end

            # 2. Set default values for version tracking
            if estimate.current_version.nil?
              estimate.update_columns(
                current_version: 1,
                total_versions: 1
              )
              puts "  ✓ Set version tracking (v1) for estimate #{estimate.id}"
              updated = true
            end

            # 3. Migrate estimate items to use item_type enum
            estimate.estimate_items.each do |item|
              item_updated = false

              # Set item_type if blank
              if item.item_type.blank?
                if item.service_id.present?
                  item.update_column(:item_type, :service)
                  item_updated = true
                elsif item.product_id.present?
                  item.update_column(:item_type, :product)
                  item_updated = true
                else
                  # Default to misc for items without associations
                  item.update_column(:item_type, :misc)
                  item_updated = true
                end
              end

              # Set position if missing
              if item.position.nil?
                max_position = estimate.estimate_items.maximum(:position) || 0
                item.update_column(:position, max_position + 1)
                item_updated = true
              end

              # Set optional defaults
              if item.optional.nil?
                item.update_columns(
                  optional: false,
                  customer_selected: true,
                  customer_declined: false
                )
                item_updated = true
              end

              migrated_items += 1 if item_updated
            end

            # 4. Create initial version snapshot for sent/viewed/approved estimates
            if estimate.sent? || estimate.viewed? || estimate.approved? || estimate.pending_payment?
              if estimate.estimate_versions.none?
                version = estimate.estimate_versions.create!(
                  version_number: 1,
                  snapshot: create_snapshot_for(estimate),
                  change_notes: "Initial version (migrated)"
                )
                puts "  ✓ Created version snapshot for estimate #{estimate.id}"
                updated = true
              end
            end

            migrated_estimates += 1 if updated

          rescue => e
            error_msg = "Error processing estimate #{estimate.id} (#{business.name}): #{e.message}"
            errors << error_msg
            puts "  ✗ #{error_msg}"
          end
        end

        puts "  Completed #{business.name}"
        puts
      end
    end

    # Summary
    puts "=" * 80
    puts "Migration Complete"
    puts "=" * 80
    puts "Total estimates processed: #{total_estimates}"
    puts "Estimates migrated: #{migrated_estimates}"
    puts "Estimate items migrated: #{migrated_items}"
    puts "Errors: #{errors.count}"
    puts

    if errors.any?
      puts "Error Details:"
      errors.each { |error| puts "  - #{error}" }
      puts
    end

    puts "✅ Migration completed successfully!" if errors.empty?
    puts "⚠️  Migration completed with #{errors.count} errors" if errors.any?
  end

  # Helper methods
  def generate_estimate_number_for(estimate, business)
    # Format: EST-YYYYMM-####
    date_prefix = (estimate.created_at || Time.current).strftime('%Y%m')
    last_estimate = business.estimates
      .where("estimate_number LIKE ?", "EST-#{date_prefix}-%")
      .order(estimate_number: :desc)
      .first

    if last_estimate && last_estimate.estimate_number =~ /EST-\d{6}-(\d{4})/
      next_number = $1.to_i + 1
    else
      next_number = 1
    end

    "EST-#{date_prefix}-#{next_number.to_s.rjust(4, '0')}"
  end

  def create_snapshot_for(estimate)
    {
      'created_at' => Time.current.iso8601,
      'estimate' => estimate.attributes,
      'items' => estimate.estimate_items.map(&:attributes),
      'customer' => {
        'name' => estimate.customer_full_name,
        'email' => estimate.customer_email,
        'phone' => estimate.customer_phone
      },
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
end
