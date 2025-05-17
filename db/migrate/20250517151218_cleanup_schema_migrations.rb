class CleanupSchemaMigrations < ActiveRecord::Migration[7.1]
  def up
    # This migration is intended to fix the issue with duplicate entries in schema_migrations
    # that causes migrations to appear multiple times in the pending migrations list
    
    # First ensure the schema_migrations table exists
    return unless connection.table_exists?(:schema_migrations)
    
    # Get all migration versions that should only appear once
    migration_versions = [
      '20250516194928', # CreateSubscriptions
      '20250516195022', # AddStripeCustomerIdToBusinesses
      '20250516195402', # FixSubscriptionsBusinessIndexUnique
      '20250517143352', # CreateIntegrations
      '20250517145833'  # FixDuplicateMigrationIssues
    ]
    
    # For each migration, ensure it appears exactly once in schema_migrations
    migration_versions.each do |version|
      # Count how many times this version appears
      count = connection.select_value("SELECT COUNT(*) FROM schema_migrations WHERE version = '#{version}'").to_i
      
      if count > 1
        # If it appears more than once, delete all occurrences
        connection.execute("DELETE FROM schema_migrations WHERE version = '#{version}'")
        # Then add it back exactly once to mark it as run
        connection.execute("INSERT INTO schema_migrations (version) VALUES ('#{version}')")
        puts "Cleaned up duplicate migration: #{version}"
      elsif count == 0
        # If it doesn't appear at all, add it (assumes the migration was actually run)
        connection.execute("INSERT INTO schema_migrations (version) VALUES ('#{version}')")
        puts "Added missing migration record: #{version}"
      else
        puts "Migration #{version} already has exactly one record, no cleanup needed"
      end
    end
  end
  
  def down
    # This migration is not reversible as it's a cleanup operation
    raise ActiveRecord::IrreversibleMigration
  end
end
