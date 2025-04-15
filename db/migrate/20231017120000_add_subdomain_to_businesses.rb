class AddSubdomainToBusinesses < ActiveRecord::Migration[8.0]
  def change
    add_column :businesses, :subdomain, :string
  end
end 