class RemoveLocaleFromUsers < ActiveRecord::Migration[8.0]
  def change
    remove_column :users, :locale, :string
  end
end
