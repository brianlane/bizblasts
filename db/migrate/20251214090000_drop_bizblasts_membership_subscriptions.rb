# frozen_string_literal: true

class DropBizblastsMembershipSubscriptions < ActiveRecord::Migration[7.1]
  def change
    drop_table :subscriptions, if_exists: true
  end
end


