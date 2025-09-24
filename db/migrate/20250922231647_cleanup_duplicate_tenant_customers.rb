class CleanupDuplicateTenantCustomers < ActiveRecord::Migration[8.0]
  def up
    say "Cleaning up duplicate tenant customers before applying unique constraint..."
    
    # Detect available columns on tenant_customers to keep this migration portable across envs
    tenant_customer_columns = connection.columns(:tenant_customers).map(&:name)
    has_user_id_column = tenant_customer_columns.include?('user_id')
    
    # Find all duplicate groups using database-agnostic approach
    # Step 1: Find all business_id + email combinations that have duplicates
    duplicate_groups_sql = <<~SQL
      SELECT business_id, LOWER(email) as normalized_email, COUNT(*) as count
      FROM tenant_customers 
      GROUP BY business_id, LOWER(email)
      HAVING COUNT(*) > 1
    SQL
    
    duplicate_groups = execute(duplicate_groups_sql).to_a
    
    duplicate_groups.each do |group|
      # Normalize and validate group values to avoid SQL injection and nil errors
      business_id = group['business_id'].to_i
      normalized_email = group['normalized_email'].to_s.downcase.strip

      if business_id <= 0 || normalized_email.empty?
        raise StandardError, "Invalid duplicate group values: business_id=#{group['business_id'].inspect}, normalized_email=#{group['normalized_email'].inspect}"
      end
      
      # Step 2: Get individual customer records for this duplicate group (database-agnostic)
      select_fields = ['id', 'first_name', 'last_name', 'phone']
      select_fields << 'user_id' if has_user_id_column
      select_fields += ['created_at', 'email']
      customers_in_group_sql = <<~SQL
        SELECT #{select_fields.join(', ')}
        FROM tenant_customers 
        WHERE business_id = #{business_id} 
        AND LOWER(email) = #{connection.quote(normalized_email)}
        ORDER BY created_at ASC, id ASC
      SQL
      
      customers_in_group = execute(customers_in_group_sql).to_a
      customer_ids = customers_in_group.map { |c| c['id'].to_i }
      
      say "  Found #{group['count']} duplicates for email '#{normalized_email}' in business #{business_id}"
      say "    Customer IDs: #{customer_ids.join(', ')}"
      
      # Keep the oldest record (first in the array)
      primary_customer_id = customer_ids.first
      duplicate_ids = customer_ids[1..-1]
      
      # Use the customer data we already fetched (no need for another query)
      primary_data = customers_in_group.first
      duplicates_data = customers_in_group[1..-1]
      
      # Safety validation: Ensure we have the expected number of records
      if customers_in_group.length != group['count'].to_i
        raise StandardError, "Data consistency error: Expected #{group['count']} customers but found #{customers_in_group.length} for email #{normalized_email} in business #{business_id}"
      end
      
      # Safety validation: Ensure primary_customer_id matches the first record
      if primary_customer_id != primary_data['id'].to_i
        raise StandardError, "Data consistency error: Primary customer ID mismatch for email #{normalized_email} in business #{business_id}"
      end
      
      # Safety validation: Ensure all records have the same normalized email
      customers_in_group.each do |customer|
        if customer['email'].to_s.downcase.strip != normalized_email
          raise StandardError, "Data consistency error: Email mismatch for customer #{customer['id']} - expected #{normalized_email}, got #{customer['email']}"
        end
      end
      
      say "    Keeping customer #{primary_customer_id} (created: #{primary_data['created_at']}) - #{primary_data['email']}"
      
      # Merge data from duplicates into primary customer
      duplicates_data.each do |duplicate_data|
        duplicate_id = duplicate_data['id']
        say "    Merging customer #{duplicate_id} (created: #{duplicate_data['created_at']})"
        
        # Build update SQL for missing data
        updates = []
        
        # Sync missing personal data
        if (primary_data['first_name'].nil? || primary_data['first_name'].to_s.strip.empty?) && 
           duplicate_data['first_name'] && !duplicate_data['first_name'].to_s.strip.empty?
          updates << "first_name = #{connection.quote(duplicate_data['first_name'])}"
          primary_data['first_name'] = duplicate_data['first_name'] # Update our local copy
        end
        
        if (primary_data['last_name'].nil? || primary_data['last_name'].to_s.strip.empty?) && 
           duplicate_data['last_name'] && !duplicate_data['last_name'].to_s.strip.empty?
          updates << "last_name = #{connection.quote(duplicate_data['last_name'])}"
          primary_data['last_name'] = duplicate_data['last_name'] # Update our local copy
        end
        
        if (primary_data['phone'].nil? || primary_data['phone'].to_s.strip.empty?) && 
           duplicate_data['phone'] && !duplicate_data['phone'].to_s.strip.empty?
          updates << "phone = #{connection.quote(duplicate_data['phone'])}"
          primary_data['phone'] = duplicate_data['phone'] # Update our local copy
        end
        
        # Sync user association if primary doesn't have one (only if the column exists)
        if has_user_id_column && primary_data['user_id'].nil? && duplicate_data['user_id']
          updates << "user_id = #{duplicate_data['user_id']}"
          primary_data['user_id'] = duplicate_data['user_id'] # Update our local copy
          say "      Transferred user_id #{duplicate_data['user_id']}"
        end
        
        # Update primary if we have changes
        if updates.any?
          execute(<<~SQL)
            UPDATE tenant_customers 
            SET #{updates.join(', ')}, updated_at = CURRENT_TIMESTAMP
            WHERE id = #{primary_customer_id}
          SQL
          say "      Updated primary customer with: #{updates.join(', ')}"
        end
        
        # Transfer related records to primary customer
        transfer_related_records(duplicate_id, primary_customer_id)
      end
      
      # Final safety check before deletion: Verify duplicate IDs match what we expect
      if duplicate_ids.length != duplicates_data.length
        raise StandardError, "Data consistency error: Duplicate IDs count (#{duplicate_ids.length}) doesn't match duplicates data count (#{duplicates_data.length})"
      end
      
      # Double-check each duplicate ID exists and belongs to the correct business/email
      duplicate_ids.each_with_index do |dup_id, index|
        expected_data = duplicates_data[index]
        if dup_id != expected_data['id'].to_i
          raise StandardError, "Data consistency error: Duplicate ID mismatch at index #{index} - expected #{expected_data['id']}, got #{dup_id}"
        end
      end
      
      # Safe to delete now - we've verified everything matches
      execute("DELETE FROM tenant_customers WHERE id IN (#{duplicate_ids.join(', ')})")
      say "    Safely deleted #{duplicate_ids.length} duplicate record(s): #{duplicate_ids.join(', ')}"
    end
    
    if duplicate_groups.empty?
      say "  No duplicate tenant customers found - data is clean!"
    else
      say "Cleanup complete. Processed #{duplicate_groups.length} duplicate group(s)."
    end
  end
  
  def down
    # This migration cannot be reversed as we've deleted duplicate records
    # and merged their data. Manual intervention would be required.
    raise ActiveRecord::IrreversibleMigration, 
          "Cannot reverse cleanup of duplicate tenant customers - data has been merged"
  end
  
  private
  
  def transfer_related_records(from_customer_id, to_customer_id)
    # Transfer all related records to the primary customer
    # Using safe queries to prevent SQL injection and database-agnostic counting
    
    # Validate input parameters to prevent injection
    from_id = from_customer_id.to_i
    to_id = to_customer_id.to_i
    
    if from_id <= 0 || to_id <= 0
      raise StandardError, "Invalid customer IDs for transfer: from=#{from_customer_id}, to=#{to_customer_id}"
    end
    
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
    
    # Transfer records for each table
    tables_to_transfer.each do |table_name|
      # First count existing records (database-agnostic)
      count_sql = "SELECT COUNT(*) as count FROM #{table_name} WHERE tenant_customer_id = #{from_id}"
      count_result = execute(count_sql).first
      record_count = count_result ? count_result['count'].to_i : 0
      
      if record_count > 0
        # Transfer records using safe integer interpolation (already validated)
        update_sql = "UPDATE #{table_name} SET tenant_customer_id = #{to_id} WHERE tenant_customer_id = #{from_id}"
        execute(update_sql)
        say "        Transferred #{record_count} #{table_name.gsub('_', ' ')}"
      end
    end
  end
end