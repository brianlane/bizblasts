class AdjustUsersForMultiStakeholder < ActiveRecord::Migration[8.0]
  def change
    # 1. Make business_id nullable
    change_column_null :users, :business_id, true
    
    # 2. Remove the old unique index scoped to business_id
    remove_index :users, name: :index_users_on_business_id_and_email, if_exists: true
    
    # 3. Add a new global unique index on email
    add_index :users, :email, unique: true, name: :index_users_on_email_unique
    
    # Optional: Change default role if :admin was 0
    # Assuming the old default was 0 (:admin), change to 3 (:client)
    # Check your user model enum definition for correct values
    change_column_default :users, :role, from: 0, to: 3
  end
end
