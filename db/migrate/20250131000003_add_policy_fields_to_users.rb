# frozen_string_literal: true

class AddPolicyFieldsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :requires_policy_acceptance, :boolean, default: false
    add_column :users, :last_policy_notification_at, :datetime
    
    add_index :users, :requires_policy_acceptance
  end
end 