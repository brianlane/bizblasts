class AddDomainCoverageToBusinesses < ActiveRecord::Migration[8.0]
  def change
    add_column :businesses, :domain_coverage_applied, :boolean, default: false
    add_column :businesses, :domain_cost_covered, :decimal, precision: 8, scale: 2
    add_column :businesses, :domain_renewal_date, :date
    add_column :businesses, :domain_coverage_notes, :text
    
    add_index :businesses, :domain_coverage_applied
    add_index :businesses, :domain_renewal_date
  end
end 