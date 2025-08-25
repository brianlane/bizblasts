class AddCustomDomainOwnedToBusiness < ActiveRecord::Migration[8.0]
  def change
    add_column :businesses, :custom_domain_owned, :boolean
  end
end
