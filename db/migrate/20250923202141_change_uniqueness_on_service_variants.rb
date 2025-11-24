class ChangeUniquenessOnServiceVariants < ActiveRecord::Migration[8.0]
  def up
    # Remove the existing unique index on (service_id, name) if present to support older tenants
    remove_index :service_variants, name: :index_service_variants_on_service_id_and_name, if_exists: true
    
    # Add new unique index on (service_id, name, duration)
    # This allows multiple variants with the same name as long as they have different durations
    add_index :service_variants,
              [:service_id, :name, :duration],
              unique: true,
              name: :index_service_variants_on_service_id_name_duration
  end
  
  def down
    # Remove the new index (if present – allows repeated down runs in CI)
    remove_index :service_variants, name: :index_service_variants_on_service_id_name_duration, if_exists: true
    
    # Restore the original unique index on (service_id, name)
    add_index :service_variants,
              [:service_id, :name],
              unique: true,
              name: :index_service_variants_on_service_id_and_name
  end
end