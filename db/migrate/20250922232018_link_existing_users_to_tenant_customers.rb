class LinkExistingUsersToTenantCustomers < ActiveRecord::Migration[8.0]
  def up
    # If the user_id column doesn't exist in this environment, safely skip
    unless column_exists?(:tenant_customers, :user_id)
      say "tenant_customers.user_id column not found; skipping user linking step."
      return
    end

    # Link existing client users to their tenant customers by email
    # and sync phone numbers from users to customers where missing
    
    say "Linking existing client users to tenant customers..."
    
    # Find all client users
    client_users = User.where(role: 'client')
    
    client_users.find_each do |user|
      say "Processing user #{user.id} (#{user.email})"
      
      # Find tenant customers with matching email
      matching_customers = TenantCustomer.where(
        email: user.email.downcase.strip,
        user_id: nil
      )
      
      matching_customers.each do |customer|
        say "  Linking customer #{customer.id} in business #{customer.business_id}"
        
        # Update customer with user_id and sync data
        updates = { user_id: user.id }
        
        # Sync phone if customer doesn't have one but user does
        if customer.phone.blank? && user.phone.present?
          updates[:phone] = user.phone
          say "    Synced phone number"
        end
        
        # Sync names if customer names are blank
        if customer.first_name.blank? && user.first_name.present?
          updates[:first_name] = user.first_name
          say "    Synced first name"
        end
        
        if customer.last_name.blank? && user.last_name.present?
          updates[:last_name] = user.last_name
          say "    Synced last name"
        end
        
        customer.update!(updates)
      end
      
      linked_count = matching_customers.count
      if linked_count > 0
        say "  Linked #{linked_count} customer record(s) to user #{user.id}"
      else
        say "  No matching unlinked customers found for user #{user.id}"
      end
    end
    
    # Report on duplicate customers that need manual resolution
    say "\nChecking for duplicate customers that need manual resolution..."
    
    duplicate_groups = TenantCustomer
      .select('business_id, LOWER(email) as normalized_email, COUNT(*) as customer_count')
      .group('business_id, LOWER(email)')
      .having('COUNT(*) > 1')
    
    duplicate_groups.each do |group|
      customers = TenantCustomer.where(
        business_id: group.business_id,
        email: TenantCustomer.where('LOWER(email) = ?', group.normalized_email).first&.email
      )
      
      linked_customers = customers.where.not(user_id: nil)
      unlinked_customers = customers.where(user_id: nil)
      
      say "Business #{group.business_id}, email #{group.normalized_email}:"
      say "  Total: #{group.customer_count}, Linked: #{linked_customers.count}, Unlinked: #{unlinked_customers.count}"
      
      if linked_customers.count > 1
        say "  WARNING: Multiple linked customers found - manual merge may be needed"
        linked_customers.each do |customer|
          say "    Customer #{customer.id} -> User #{customer.user_id}"
        end
      end
    end
    
    total_linked = TenantCustomer.where.not(user_id: nil).count
    total_unlinked = TenantCustomer.where(user_id: nil).count
    
    say "\nMigration complete!"
    say "Linked customers: #{total_linked}"
    say "Unlinked customers (guests): #{total_unlinked}"
  end
  
  def down
    # If the user_id column doesn't exist, nothing to unlink
    unless column_exists?(:tenant_customers, :user_id)
      say "tenant_customers.user_id column not found; nothing to unlink."
      return
    end

    say "Unlinking all users from tenant customers..."
    
    # Remove all user_id links
    updated_count = TenantCustomer.where.not(user_id: nil).update_all(user_id: nil)
    
    say "Unlinked #{updated_count} customer records from users"
  end
end