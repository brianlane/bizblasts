class AddCnameFieldsToBusinesses < ActiveRecord::Migration[8.0]
  def change
    add_column :businesses, :cname_setup_email_sent_at, :datetime
    add_column :businesses, :cname_monitoring_active, :boolean, default: false, null: false
    add_column :businesses, :cname_check_attempts, :integer, default: 0, null: false
    add_column :businesses, :render_domain_added, :boolean, default: false, null: false
    
    # Add index for performance (status index already exists)
    add_index :businesses, :cname_monitoring_active
  end
end
