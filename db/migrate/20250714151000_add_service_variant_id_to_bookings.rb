class AddServiceVariantIdToBookings < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    add_reference :bookings, :service_variant, foreign_key: { to_table: :service_variants }, index: true, null: true

    say_with_time "Creating default service variants and attaching to bookings" do
      Service.find_each do |service|
        variant = service.service_variants.create!(
          name: 'Default',
          duration: service.duration,
          price: service.price,
          active: service.active,
          position: 0
        )

        Booking.where(service_id: service.id).find_in_batches(batch_size: 1_000) do |batch|
          Booking.where(id: batch.map(&:id)).update_all(service_variant_id: variant.id)
        end
      end
    end
  end

  def down
    remove_reference :bookings, :service_variant, index: true, foreign_key: true
    ServiceVariant.delete_all
    drop_table :service_variants if table_exists?(:service_variants)
  end
end 