class MarkSubscriptionTablesAsApplied < ActiveRecord::Migration[8.0]
  def up
    # The customer_subscriptions and subscription_transactions tables already exist
    # in the database but their migrations were missing from version control.
    # 
    # We need to mark the previous migrations as applied without actually
    # running them, since the tables already exist.
    
    # Check if tables exist before marking migrations as applied
    if table_exists?(:customer_subscriptions) && table_exists?(:subscription_transactions)
      say "Tables customer_subscriptions and subscription_transactions already exist"
      say "Marking previous migrations as applied..."
      
      # Insert the migration records directly to mark them as applied
      connection.execute <<-SQL
        INSERT INTO schema_migrations (version) 
        VALUES ('20250614222120'), ('20250614222148')
        ON CONFLICT (version) DO NOTHING;
      SQL
      
      say "Subscription table migrations marked as applied"
    else
      raise "Expected tables do not exist. Please run migrations normally."
    end
  end

  def down
    # Remove the migration records if we need to rollback
    connection.execute <<-SQL
      DELETE FROM schema_migrations 
      WHERE version IN ('20250614222120', '20250614222148');
    SQL
    
    say "Subscription table migration records removed"
  end
end
