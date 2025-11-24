class AddIndexToBusinessesWebsiteLayout < ActiveRecord::Migration[8.1]
  def change
    add_index :businesses, :website_layout, if_not_exists: true
  end
end
