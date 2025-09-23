class CleanupDuplicateTenantCustomers < ActiveRecord::Migration[8.0]
  def up
    say "Cleaning up duplicate tenant customers before applying unique constraint..."
    
    # Find all duplicate groups (same business_id and email, case-insensitive)
    duplicate_groups = execute(<<~SQL)
      SELECT business_id, LOWER(email) as normalized_email, COUNT(*) as count, 
             ARRAY_AGG(id ORDER BY created_at ASC) as customer_ids
      FROM tenant_customers 
      GROUP BY business_id, LOWER(email)
      HAVING COUNT(*) > 1
    SQL
    
    duplicate_groups.each do |group|
      business_id = group['business_id']
      normalized_email = group['normalized_email']
      customer_ids = group['customer_ids'].gsub(/[{}]/, '').split(',').map(&:to_i)
      
      say "  Found #{group['count']} duplicates for email '#{normalized_email}' in business #{business_id}"
      say "    Customer IDs: #{customer_ids.join(', ')}"
      
      # Keep the oldest record (first in the array)
      primary_customer_id = customer_ids.first
      duplicate_ids = customer_ids[1..-1]
      
      # Get details about the customers we're merging
      customers = TenantCustomer.where(id: customer_ids).order(:created_at)
      primary = customers.first
      duplicates = customers[1..-1]
      
      say "    Keeping customer #{primary_customer_id} (created: #{primary.created_at})"
      
      # Merge data from duplicates into primary customer
      duplicates.each do |duplicate|
        say "    Merging customer #{duplicate.id} (created: #{duplicate.created_at})"
        
        # Update primary with any missing data from duplicate
        updates = {}
        
        # Sync missing personal data
        updates[:first_name] = duplicate.first_name if primary.first_name.blank? && duplicate.first_name.present?
        updates[:last_name] = duplicate.last_name if primary.last_name.blank? && duplicate.last_name.present?
        updates[:phone] = duplicate.phone if primary.phone.blank? && duplicate.phone.present?
        
        # Sync user association if primary doesn't have one
        if primary.user_id.nil? && duplicate.user_id.present?
          updates[:user_id] = duplicate.user_id
          say "      Transferred user_id #{duplicate.user_id}"
        end
        
        # Update primary if we have changes
        if updates.any?
          execute(<<~SQL)
            UPDATE tenant_customers 
            SET #{updates.map { |k, v| "#{k} = #{connection.quote(v)}" }.join(', ')},
                updated_at = NOW()
            WHERE id = #{primary_customer_id}
          SQL
          say "      Updated primary customer with: #{updates.keys.join(', ')}"
        end
        
        # Transfer related records to primary customer
        transfer_related_records(duplicate.id, primary_customer_id)
      end
      
      # Delete the duplicate records
      execute("DELETE FROM tenant_customers WHERE id IN (#{duplicate_ids.join(', ')})")
      say "    Deleted #{duplicate_ids.length} duplicate record(s)"
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
    
    # Bookings
    booking_count = execute("UPDATE bookings SET tenant_customer_id = #{to_customer_id} WHERE tenant_customer_id = #{from_customer_id}").cmd_tuples
    say "        Transferred #{booking_count} booking(s)" if booking_count > 0
    
    # Invoices  
    invoice_count = execute("UPDATE invoices SET tenant_customer_id = #{to_customer_id} WHERE tenant_customer_id = #{from_customer_id}").cmd_tuples
    say "        Transferred #{invoice_count} invoice(s)" if invoice_count > 0
    
    # Orders
    order_count = execute("UPDATE orders SET tenant_customer_id = #{to_customer_id} WHERE tenant_customer_id = #{from_customer_id}").cmd_tuples
    say "        Transferred #{order_count} order(s)" if order_count > 0
    
    # Payments
    payment_count = execute("UPDATE payments SET tenant_customer_id = #{to_customer_id} WHERE tenant_customer_id = #{from_customer_id}").cmd_tuples
    say "        Transferred #{payment_count} payment(s)" if payment_count > 0
    
    # SMS Messages
    sms_count = execute("UPDATE sms_messages SET tenant_customer_id = #{to_customer_id} WHERE tenant_customer_id = #{from_customer_id}").cmd_tuples
    say "        Transferred #{sms_count} SMS message(s)" if sms_count > 0
    
    # Loyalty transactions
    loyalty_count = execute("UPDATE loyalty_transactions SET tenant_customer_id = #{to_customer_id} WHERE tenant_customer_id = #{from_customer_id}").cmd_tuples
    say "        Transferred #{loyalty_count} loyalty transaction(s)" if loyalty_count > 0
    
    # Loyalty redemptions
    redemption_count = execute("UPDATE loyalty_redemptions SET tenant_customer_id = #{to_customer_id} WHERE tenant_customer_id = #{from_customer_id}").cmd_tuples
    say "        Transferred #{redemption_count} loyalty redemption(s)" if redemption_count > 0
    
    # Customer subscriptions
    subscription_count = execute("UPDATE customer_subscriptions SET tenant_customer_id = #{to_customer_id} WHERE tenant_customer_id = #{from_customer_id}").cmd_tuples
    say "        Transferred #{subscription_count} subscription(s)" if subscription_count > 0
    
    # Subscription transactions
    sub_transaction_count = execute("UPDATE subscription_transactions SET tenant_customer_id = #{to_customer_id} WHERE tenant_customer_id = #{from_customer_id}").cmd_tuples
    say "        Transferred #{sub_transaction_count} subscription transaction(s)" if sub_transaction_count > 0
  end
end