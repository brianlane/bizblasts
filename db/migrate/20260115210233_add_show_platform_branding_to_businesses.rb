class AddShowPlatformBrandingToBusinesses < ActiveRecord::Migration[8.1]
  def change
    add_column :businesses, :show_platform_branding, :boolean, default: true, null: false
  end
end
