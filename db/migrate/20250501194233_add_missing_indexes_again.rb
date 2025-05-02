class AddMissingIndexesAgain < ActiveRecord::Migration[8.0]
  def change
    # Add indexes for frequently queried columns or foreign keys not already indexed
    add_index :products, :active
    add_index :products, :featured
    add_index :shipping_methods, :active
    # Add any other necessary indexes based on query patterns
  end
end
