class AddPlivoToIntegrationCredentials < ActiveRecord::Migration[8.0]
  def up
    # Add plivo as option 3 to the provider enum
    # Note: We don't need to modify the database column since Rails enums are stored as integers
    # The model change is sufficient, but we create this migration for documentation
    # and to ensure any existing data constraints are properly handled
    
    # No database changes needed - Rails enum handles this automatically
    # This migration serves as documentation of the schema change
  end

  def down
    # Rollback would require removing any plivo records
    # We'll leave this empty as it's safer to handle manually if needed
  end
end
