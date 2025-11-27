class AddEstimateTrackingToServices < ActiveRecord::Migration[8.1]
  def change
    add_reference :services, :created_from_estimate, foreign_key: { to_table: :estimates }, null: true
  end
end
