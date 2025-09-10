class AddHealthStatusToBusinesses < ActiveRecord::Migration[8.0]
  def change
    add_column :businesses, :domain_health_verified, :boolean, default: false, null: false
    add_column :businesses, :domain_health_checked_at, :datetime
    
    # Add index for querying businesses needing health checks
    add_index :businesses, [:host_type, :status, :domain_health_verified], name: 'index_businesses_on_custom_domain_health'
  end
end
