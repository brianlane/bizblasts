class AddStatusToBusinesses < ActiveRecord::Migration[8.0]
  def up
    # Add status column if it doesn't exist (production fix)
    unless column_exists?(:businesses, :status)
      add_column :businesses, :status, :string, null: false, default: 'active'
      say "Added status column with default 'active'"
    else
      # Column exists but may have wrong default - fix it to match the model
      current_default = connection.columns(:businesses).find { |c| c.name == 'status' }&.default
      if current_default != 'active'
        change_column_default :businesses, :status, from: current_default, to: 'active'
        say "Changed status column default from '#{current_default}' to 'active'"
      end
    end
    
    # Add index if it doesn't exist (handles both missing column and missing index cases)
    unless index_exists?(:businesses, :status)
      add_index :businesses, :status
      say "Added index on status column"
    end
  end

  def down
    # Conservative rollback approach:
    # - Always remove index if it exists (safe operation)
    # - Never remove column (too risky - could lose data)
    # - Only revert default if it matches what we would have set
    
    if index_exists?(:businesses, :status)
      remove_index :businesses, :status
      say "Removed status index"
    end
    
    if column_exists?(:businesses, :status)
      current_default = connection.columns(:businesses).find { |c| c.name == 'status' }&.default
      
      # Only revert default if it matches what this migration would set
      if current_default == 'active'
        change_column_default :businesses, :status, from: 'active', to: 'pending'
        say "Reverted status column default from 'active' to 'pending'"
      end
      
      say "Note: status column not removed to prevent data loss."
      say "If column was added by this migration and needs removal, create a separate migration."
    end
  end
end
