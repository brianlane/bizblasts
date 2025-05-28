class CleanupOrphanedMigrations < ActiveRecord::Migration[8.0]
  def up
    # Remove orphaned migration entries that have no corresponding files
    # These were causing "NO FILE" entries in db:migrate:status
    orphaned_versions = ['20250526182339', '20250526194538']
    
    orphaned_versions.each do |version|
      # Check if the migration entry exists before trying to delete it
      if ActiveRecord::Base.connection.execute("SELECT 1 FROM schema_migrations WHERE version = '#{version}'").any?
        ActiveRecord::Base.connection.execute("DELETE FROM schema_migrations WHERE version = '#{version}'")
        puts "Removed orphaned migration entry: #{version}"
      end
    end
  end

  def down
    # This migration is irreversible since we don't know what the original migrations did
    # and their files no longer exist. This is a cleanup operation only.
    raise ActiveRecord::IrreversibleMigration, "Cannot restore orphaned migration entries"
  end
end
