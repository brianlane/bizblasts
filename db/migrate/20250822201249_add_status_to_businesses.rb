class AddStatusToBusinesses < ActiveRecord::Migration[8.0]
  def up
    # Add status column if it doesn't exist (production fix)
    unless column_exists?(:businesses, :status)
      add_column :businesses, :status, :string, null: false, default: 'active'
    else
      # Column exists but may have wrong default - fix it to match the model
      change_column_default :businesses, :status, from: 'pending', to: 'active'
    end
    
    # Add index if it doesn't exist (handles both missing column and missing index cases)
    unless index_exists?(:businesses, :status)
      add_index :businesses, :status
    end
  end

  def down
    # Remove index if it exists
    if index_exists?(:businesses, :status)
      remove_index :businesses, :status
    end
    
    # If we added the column, remove it; if we changed default, revert it
    if column_exists?(:businesses, :status)
      # Try to determine if this migration added the column or just changed the default
      # If most records have NULL status, we probably added the column
      total_businesses = connection.execute("SELECT COUNT(*) FROM businesses").first['count'].to_i
      null_status_count = connection.execute("SELECT COUNT(*) FROM businesses WHERE status IS NULL").first['count'].to_i
      
      if total_businesses > 0 && null_status_count.to_f / total_businesses > 0.5
        # More than 50% have NULL status, we probably added the column
        remove_column :businesses, :status
      else
        # Column existed before, just revert the default
        change_column_default :businesses, :status, from: 'active', to: 'pending'
      end
    end
  end
end
