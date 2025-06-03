class RemoveCascadeDeleteFromUsersBusinessForeignKey < ActiveRecord::Migration[8.0]
  def change
    remove_foreign_key :users, :businesses
    add_foreign_key    :users, :businesses, column: :business_id
  end
end 