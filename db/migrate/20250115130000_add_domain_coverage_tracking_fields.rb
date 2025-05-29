class AddDomainCoverageTrackingFields < ActiveRecord::Migration[8.0]
  def change
    add_column :businesses, :domain_auto_renewal_enabled, :boolean, default: false
    add_column :businesses, :domain_coverage_expires_at, :date
    add_column :businesses, :domain_registrar, :string
    add_column :businesses, :domain_registration_date, :date
    
    add_index :businesses, :domain_coverage_expires_at
    add_index :businesses, :domain_auto_renewal_enabled
  end
end 