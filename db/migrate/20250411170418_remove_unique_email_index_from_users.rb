class RemoveUniqueEmailIndexFromUsers < ActiveRecord::Migration[7.1]
  def change
    # Remove the unique index on the email column
    remove_index :users, name: :index_users_on_email_unique, if_exists: true

    # Optional: Add a non-unique index back if querying by email is still frequent,
    # but uniqueness is handled at the application level.
    # add_index :users, :email, name: :index_users_on_email, if_not_exists: true
  end
end
