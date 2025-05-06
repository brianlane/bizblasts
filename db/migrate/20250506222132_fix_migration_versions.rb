class FixMigrationVersions < ActiveRecord::Migration[8.0]
  def up
    # Map old migration versions to new ones
    version_map = {
      '20250505180003' => '20250506215552', # AddPrimaryAndPositionToActiveStorageAttachments
      '20250505180004' => '20250506215553'  # AddStockQuantityToProducts
    }

    # For each old version, add the new version if not already present and remove the old version
    version_map.each do |old_version, new_version|
      execute <<-SQL
        INSERT INTO schema_migrations (version)
        SELECT '#{new_version}'
        WHERE NOT EXISTS (
          SELECT 1 FROM schema_migrations WHERE version = '#{new_version}'
        );
        
        DELETE FROM schema_migrations WHERE version = '#{old_version}';
      SQL
    end
  end

  def down
    # This migration is not reversible
    raise ActiveRecord::IrreversibleMigration
  end
end
