class AddTierAndDomainToBusinesses < ActiveRecord::Migration[8.0]
  def change
    add_column :businesses, :tier, :string
    add_column :businesses, :domain, :string
    add_index :businesses, :domain, unique: true
  end
end
