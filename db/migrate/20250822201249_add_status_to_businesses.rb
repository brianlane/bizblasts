class AddStatusToBusinesses < ActiveRecord::Migration[8.0]
  def change
    # Add status column if it doesn't exist (production fix)
    unless column_exists?(:businesses, :status)
      add_column :businesses, :status, :string, null: false, default: 'active'
      add_index :businesses, :status
    end
  end
end
