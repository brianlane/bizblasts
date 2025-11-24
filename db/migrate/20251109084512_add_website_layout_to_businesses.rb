class AddWebsiteLayoutToBusinesses < ActiveRecord::Migration[7.1]
  def change
    add_column :businesses, :website_layout, :string, null: false, default: 'basic'
    add_index :businesses, :website_layout
  end
end

