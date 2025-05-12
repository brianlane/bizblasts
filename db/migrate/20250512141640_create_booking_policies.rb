class CreateBookingPolicies < ActiveRecord::Migration[8.0]
  def change
    create_table :booking_policies do |t|
      t.references :business, null: false, foreign_key: true
      t.integer :cancellation_window_mins
      t.integer :buffer_time_mins
      t.integer :max_daily_bookings
      t.integer :max_advance_days
      t.jsonb :intake_fields

      t.timestamps
    end
  end
end
