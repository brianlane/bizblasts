# frozen_string_literal: true

# Migration to update the users email index to be scoped to company_id
class UpdateUsersEmailIndex < ActiveRecord::Migration[8.0]
  def up
    # Remove the old index
    remove_index :users, :email, unique: true, if_exists: true
    
    # Add the new composite index
    add_index :users, [:company_id, :email], unique: true
  end
  
  def down
    # Remove the composite index
    remove_index :users, [:company_id, :email], if_exists: true
    
    # Restore the old index
    add_index :users, :email, unique: true
  end
end
