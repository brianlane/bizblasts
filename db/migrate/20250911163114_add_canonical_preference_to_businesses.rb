class AddCanonicalPreferenceToBusinesses < ActiveRecord::Migration[8.0]
  def change
    add_column :businesses, :canonical_preference, :string, default: 'www', null: false,
               comment: 'Preferred canonical version: "www" or "apex" for custom domains'
    
    add_index :businesses, :canonical_preference
  end
end
