class FixDuplicateMigrationIssues < ActiveRecord::Migration[7.1]
  def up
    # First check if the subscriptions table exists
    if table_exists?(:subscriptions)
      # Check if the index exists and remove it safely if it does
      if index_exists?(:subscriptions, :business_id)
        remove_index :subscriptions, :business_id, if_exists: true
      end
      
      # Add the index back with the correct options (if needed)
      # Note: We use if_not_exists: true to prevent errors if it's added in another migration
      add_index :subscriptions, :business_id, unique: true, if_not_exists: true
    end
    
    # Fix for the stripe_subscription_id index if needed
    if table_exists?(:subscriptions) && index_exists?(:subscriptions, :stripe_subscription_id)
      remove_index :subscriptions, :stripe_subscription_id, if_exists: true
      add_index :subscriptions, :stripe_subscription_id, unique: true, if_not_exists: true
    end
  end

  def down
    # This migration is idempotent, so down can be a no-op
    # or you could ensure the indexes exist as they should
  end
end
