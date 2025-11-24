class ConsolidatedTenantCustomerCleanupAndIndex < ActiveRecord::Migration[8.0]
  def up
    # This migration combines data cleanup and unique constraint application
    # in a single transaction to ensure data integrity
    
    say "Starting consolidated tenant customer cleanup and unique constraint application..."
    
    # Wrap everything in a transaction for atomicity
    transaction do
      cleanup_duplicate_tenant_customers
      add_unique_constraint
      add_performance_indexes
    end
    
    say "Consolidated cleanup and indexing complete!"
  end
  
  def down
    # Remove indexes and constraints (data cleanup is irreversible)
    transaction do
      remove_index :tenant_customers, name: 'index_tenant_customers_on_business_id_and_lower_email', if_exists: true
      remove_index :tenant_customers, name: 'index_tenant_customers_on_lower_email', if_exists: true
    end
    
    # Note: Cannot reverse the data cleanup as duplicates have been merged and deleted
    say "Removed indexes (data cleanup cannot be reversed)"
  end
  
  private
  
  def cleanup_duplicate_tenant_customers
    say "Phase 1: Cleaning up duplicate tenant customers..."
    
    # Detect available columns on tenant_customers to keep this migration portable across envs
    tenant_customer_columns = connection.columns(:tenant_customers).map(&:name)
    has_user_id_column = tenant_customer_columns.include?('user_id')
    
    # Use window functions to identify duplicates and primary records in one query
    select_fields = ['id', 'business_id', 'email', 'first_name', 'last_name', 'phone', 'created_at']
    select_fields << 'user_id' if has_user_id_column
    
    # Single query to identify all duplicates and their primaries using window functions
    duplicates_sql = <<~SQL
      WITH ranked_customers AS (
        SELECT #{select_fields.join(', ')},
               ROW_NUMBER() OVER (
                 PARTITION BY business_id, LOWER(email) 
                 ORDER BY created_at ASC, id ASC
               ) as rn,
               COUNT(*) OVER (
                 PARTITION BY business_id, LOWER(email)
               ) as duplicate_count
        FROM tenant_customers
      )
      SELECT * FROM ranked_customers 
      WHERE duplicate_count > 1
      ORDER BY business_id, LOWER(email), rn
    SQL
    
    duplicates = execute(duplicates_sql).to_a
    
    if duplicates.empty?
      say "  No duplicate tenant customers found - data is clean!"
      return
    end
    
    # Group by business_id + normalized_email for processing
    grouped_duplicates = duplicates.group_by do |row|
      [row['business_id'].to_i, row['email'].downcase.strip]
    end
    
    say "  Found #{grouped_duplicates.size} duplicate groups affecting #{duplicates.size} records"
    
    # Process each group
    grouped_duplicates.each do |(business_id, normalized_email), group_records|
      # First record (rn=1) is the primary, rest are duplicates
      primary_record = group_records.find { |r| r['rn'].to_i == 1 }
      duplicate_records = group_records.select { |r| r['rn'].to_i > 1 }
      
      primary_id = primary_record['id'].to_i
      duplicate_ids = duplicate_records.map { |r| r['id'].to_i }
      
      say "    Processing #{group_records.size} duplicates for '#{normalized_email}' in business #{business_id}"
      
      # Merge data from duplicates into primary
      duplicate_records.each do |duplicate|
        merge_customer_data(primary_record, duplicate, has_user_id_column)
      end
      
      # Transfer all related records from duplicates to primary
      transfer_related_records_batch(duplicate_ids, primary_id)
      
      # Delete duplicates in batch
      execute("DELETE FROM tenant_customers WHERE id IN (#{duplicate_ids.join(', ')})")
      say "      Deleted #{duplicate_ids.size} duplicate record(s)"
    end
    
    say "  Phase 1 complete: Processed #{grouped_duplicates.size} duplicate group(s)"
  end
  
  def add_unique_constraint
    say "Phase 2: Adding unique constraint on business_id + LOWER(email)..."
    
    # Check if index exists by name directly
    existing_indexes = connection.indexes(:tenant_customers).map(&:name)
    
    unless existing_indexes.include?('index_tenant_customers_on_business_id_and_lower_email')
      add_index :tenant_customers, 
                'business_id, LOWER(email)', 
                unique: true, 
                name: 'index_tenant_customers_on_business_id_and_lower_email'
      say "  Unique constraint added successfully"
    else
      say "  Unique constraint already exists - skipping"
    end
  end
  
  def add_performance_indexes
    say "Phase 3: Adding performance indexes..."
    
    # Check if index exists by name directly
    existing_indexes = connection.indexes(:tenant_customers).map(&:name)
    
    unless existing_indexes.include?('index_tenant_customers_on_lower_email')
      add_index :tenant_customers, 'LOWER(email)', name: 'index_tenant_customers_on_lower_email'
      say "  Performance indexes added successfully"
    else
      say "  Performance index already exists - skipping"
    end
  end
  
  def merge_customer_data(primary_data, duplicate_data, has_user_id_column)
    updates = []
    
    # Merge non-blank data from duplicate into primary
    %w[first_name last_name phone].each do |field|
      if (primary_data[field].nil? || primary_data[field].to_s.strip.empty?) &&
         duplicate_data[field] && !duplicate_data[field].to_s.strip.empty?
        updates << "#{field} = #{connection.quote(duplicate_data[field])}"
        primary_data[field] = duplicate_data[field] # Update local copy
      end
    end
    
    # Sync user association if primary doesn't have one (only if the column exists)
    if has_user_id_column && primary_data['user_id'].nil? && duplicate_data['user_id']
      updates << "user_id = #{duplicate_data['user_id']}"
      primary_data['user_id'] = duplicate_data['user_id'] # Update local copy
    end
    
    # Keep the earlier created_at date
    if duplicate_data['created_at'] && primary_data['created_at'] && 
       Time.parse(duplicate_data['created_at'].to_s) < Time.parse(primary_data['created_at'].to_s)
      updates << "created_at = #{connection.quote(duplicate_data['created_at'])}"
    end
    
    # Update primary if we have changes
    if updates.any?
      primary_id = primary_data['id'].to_i
      execute(<<~SQL)
        UPDATE tenant_customers 
        SET #{updates.join(', ')}, updated_at = CURRENT_TIMESTAMP
        WHERE id = #{primary_id}
      SQL
    end
  end
  
  def transfer_related_records_batch(duplicate_ids, primary_id)
    return if duplicate_ids.empty?
    
    # Define tables to transfer
    tables_to_transfer = [
      'bookings',
      'invoices', 
      'orders',
      'payments',
      'sms_messages',
      'loyalty_transactions',
      'loyalty_redemptions',
      'customer_subscriptions',
      'subscription_transactions'
    ]
    
    # Transfer records for each table in batch
    tables_to_transfer.each do |table_name|
      # Count and transfer in one operation
      update_sql = <<~SQL
        UPDATE #{table_name} 
        SET tenant_customer_id = #{primary_id} 
        WHERE tenant_customer_id IN (#{duplicate_ids.join(', ')})
      SQL
      
      affected_rows = execute(update_sql).cmd_tuples || 0
      
      if affected_rows > 0
        say "        Transferred #{affected_rows} #{table_name.gsub('_', ' ')}"
      end
    end
  end
end