class UserSidebarItem < ApplicationRecord
  belongs_to :user

  validates :item_key, presence: true
  validates :position, presence: true, numericality: { only_integer: true }
  validates :visible, inclusion: { in: [true, false] }

  # Returns the default sidebar items (as an array of hashes)
  def self.default_items_for(user)
    items = [
      { key: 'dashboard', label: 'Dashboard' },
      { key: 'bookings', label: 'Bookings' },
      { key: 'website', label: 'Website' },
      { key: 'website_builder', label: 'Website Builder', tier: %w[standard premium] },
      { key: 'transactions', label: 'Transactions' },
      { key: 'payments', label: 'Payments' },
      { key: 'staff', label: 'Staff' },
      { key: 'services', label: 'Services' },
      { key: 'products', label: 'Products' },
      { key: 'shipping_methods', label: 'Shipping Methods' },
      { key: 'tax_rates', label: 'Tax Rates' },
      { key: 'customers', label: 'Customers' },
      { key: 'referrals', label: 'Referrals' },
      { key: 'loyalty', label: 'Loyalty' },
      { key: 'platform', label: 'BizBlasts Rewards' },
      { key: 'promotions', label: 'Promotions' },
      { key: 'customer_subscriptions', label: 'Subscriptions' },
      { key: 'settings', label: 'Settings' }
    ]
    # Filter Website Builder by business tier
    business = user.business if user.respond_to?(:business)
    unless business&.standard_tier? || business&.premium_tier?
      items.reject! { |i| i[:key] == 'website_builder' }
    end
    items
  end
end 