class AddFeaturedAndAvailabilityToServices < ActiveRecord::Migration[8.0]
  def change
    add_column :services, :featured, :boolean
    add_column :services, :availability_settings, :jsonb
  end
end
