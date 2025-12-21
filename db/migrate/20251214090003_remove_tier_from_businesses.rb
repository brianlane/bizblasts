# frozen_string_literal: true

class RemoveTierFromBusinesses < ActiveRecord::Migration[7.1]
  def change
    remove_column :businesses, :tier, :string, if_exists: true
  end
end



