class AddDescriptionIndexToBusinesses < ActiveRecord::Migration[8.0]
  def change
    add_index :businesses, :description
  end
end
