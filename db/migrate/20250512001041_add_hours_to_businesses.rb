class AddHoursToBusinesses < ActiveRecord::Migration[8.0]
  def change
    add_column :businesses, :hours, :jsonb
  end
end
