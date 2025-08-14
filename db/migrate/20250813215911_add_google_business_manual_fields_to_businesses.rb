class AddGoogleBusinessManualFieldsToBusinesses < ActiveRecord::Migration[8.0]
  def change
    add_column :businesses, :google_business_name, :string
    add_column :businesses, :google_business_address, :text
    add_column :businesses, :google_business_phone, :string
    add_column :businesses, :google_business_website, :string
    add_column :businesses, :google_business_manual, :boolean, default: false
    
    # Add index for efficient queries
    add_index :businesses, :google_business_manual
  end
end
