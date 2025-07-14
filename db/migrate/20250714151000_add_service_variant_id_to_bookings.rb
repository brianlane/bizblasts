class AddServiceVariantIdToBookings < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    unless column_exists?(:bookings, :service_variant_id)
      add_reference :bookings, :service_variant, foreign_key: { to_table: :service_variants }, index: true, null: true
    end

    say_with_time "Creating default service variants and attaching to bookings" do
      Service.find_each do |service|
        # Either fetch the existing default variant or create it if it doesn't exist
        variant = service.service_variants.find_or_create_by!(name: 'Default') do |v|
          v.duration = service.duration
          v.price    = service.price
          v.active   = service.active
          v.position = 0
        end

        # Attach variant to bookings that don't have one yet
        Booking.where(service_id: service.id, service_variant_id: nil).find_in_batches(batch_size: 1_000) do |batch|
          Booking.where(id: batch.map(&:id)).update_all(service_variant_id: variant.id)
        end
      end
    end
  end

  def down
    # Remove the foreign key and column from bookings first to avoid FK violations
    if column_exists?(:bookings, :service_variant_id)
      remove_reference :bookings, :service_variant, index: true, foreign_key: true
    end

    # Optionally, clean up variants that were created by this migration and are no longer referenced.
    # Keeping the records is generally safe, but remove them if desired:
    # execute "DELETE FROM service_variants WHERE name = 'Default'"

    # NOTE: We intentionally do NOT drop the service_variants table here because
    # it was created in a separate migration (20250714150000_create_service_variants).
    # Dropping it here would break the migration chain and cause rollback failures.
  end
end 