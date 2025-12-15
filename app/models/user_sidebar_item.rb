# frozen_string_literal: true

class UserSidebarItem < ApplicationRecord
  belongs_to :user

  validates :item_key, presence: true
  validates :position, presence: true, numericality: { only_integer: true }
  validates :visible, inclusion: { in: [true, false] }

  # Returns the default sidebar items (derived from SidebarItems - the single source of truth)
  def self.default_items_for(user)
    SidebarItems.all_items(user: user)
  end
end
