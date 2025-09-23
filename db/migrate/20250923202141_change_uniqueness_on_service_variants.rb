class ChangeUniquenessOnServiceVariants < ActiveRecord::Migration[7.1]
  def change
    # Remove the existing unique index on (service_id, name)
    remove_index :service_variants, name: :index_service_variants_on_service_id_and_name
    
    # Add new unique index on (service_id, name, duration)
    # This allows multiple variants with the same name as long as they have different durations
    add_index :service_variants,
              [:service_id, :name, :duration],
              unique: true,
              name: :index_service_variants_on_service_id_name_duration
  end
end