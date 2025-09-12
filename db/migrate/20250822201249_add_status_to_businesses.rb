class AddStatusToBusinesses < ActiveRecord::Migration[8.0]
  def up
    # Store original state for rollback
    original_default = nil
    column_existed = column_exists?(:businesses, :status)
    
    if column_existed
      original_default = connection.columns(:businesses).find { |c| c.name == 'status' }&.default
    end
    
    # Store this information for the down migration
    connection.execute <<~SQL
      CREATE TABLE IF NOT EXISTS migration_metadata_20250822201249 (
        key VARCHAR(50) PRIMARY KEY,
        value TEXT
      )
    SQL
    
    # Use proper SQL escaping to prevent injection and handle special characters
    escaped_column_existed = connection.quote(column_existed.to_s)
    escaped_original_default = original_default ? connection.quote(original_default) : 'NULL'
    
    connection.execute <<~SQL
      INSERT INTO migration_metadata_20250822201249 (key, value) 
      VALUES ('column_existed', #{escaped_column_existed})
      ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value
    SQL
    
    connection.execute <<~SQL
      INSERT INTO migration_metadata_20250822201249 (key, value) 
      VALUES ('original_default', #{escaped_original_default})
      ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value
    SQL
    
    # Add status column if it doesn't exist (production fix)
    unless column_existed
      add_column :businesses, :status, :string, null: false, default: 'active'
      say "Added status column with default 'active'"
    else
      # Column exists but may have wrong default - fix it to match the model
      if original_default != 'active'
        change_column_default :businesses, :status, from: original_default, to: 'active'
        say "Changed status column default from '#{original_default}' to 'active'"
      else
        say "Status column already has correct default 'active'"
      end
    end
    
    # Add index if it doesn't exist (handles both missing column and missing index cases)
    unless index_exists?(:businesses, :status)
      add_index :businesses, :status
      say "Added index on status column"
    end
  end

  def down
    # Retrieve original state information
    metadata_exists = connection.table_exists?('migration_metadata_20250822201249')
    column_existed = false
    original_default = nil
    
    if metadata_exists
      result = connection.execute("SELECT key, value FROM migration_metadata_20250822201249")
      result.each do |row|
        key = row['key'] || row[0]  # Handle different DB adapter result formats
        value = row['value'] || row[1]
        
        case key
        when 'column_existed'
          column_existed = value.to_s == 'true'
        when 'original_default'
          original_default = value == 'NULL' ? nil : value
        end
      end
    end
    
    # Remove index if it exists
    if index_exists?(:businesses, :status)
      remove_index :businesses, :status
      say "Removed status index"
    end
    
    if column_exists?(:businesses, :status)
      if column_existed && metadata_exists
        # Column existed before migration - restore original default
        current_default = connection.columns(:businesses).find { |c| c.name == 'status' }&.default
        
        if current_default == 'active' && original_default != 'active'
          if original_default.nil?
            # Original had no default
            connection.execute("ALTER TABLE businesses ALTER COLUMN status DROP DEFAULT")
            say "Removed default from status column (restored original state)"
          else
            change_column_default :businesses, :status, from: 'active', to: original_default
            say "Reverted status column default from 'active' to '#{original_default}'"
          end
        end
        
        say "Note: status column not removed as it existed before this migration."
      else
        # Column was added by this migration or we can't determine - be conservative
        say "Note: status column not removed to prevent data loss."
        say "If column was added by this migration and needs removal, create a separate migration."
      end
    end
    
    # Clean up metadata table
    if metadata_exists
      connection.execute("DROP TABLE migration_metadata_20250822201249")
      say "Cleaned up migration metadata"
    end
  end
end
