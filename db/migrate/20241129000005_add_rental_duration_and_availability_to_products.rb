class AddRentalDurationAndAvailabilityToProducts < ActiveRecord::Migration[7.1]
  def change
    add_column :products, :rental_duration_options, :jsonb, default: [], null: false
    add_column :products, :rental_availability_schedule, :jsonb, default: {}, null: false
    add_index :products, :rental_availability_schedule, using: :gin
  end
end

