# frozen_string_literal: true

# Helper for business registration sidebar selection
module BusinessRegistrationsHelper
  # Returns sidebar items suitable for registration form selection
  # All items are shown - conditional filtering happens at runtime when rendering the sidebar
  def sidebar_registration_items
    [
      { key: 'dashboard', label: 'Dashboard' },
      { key: 'bookings', label: 'Bookings' },
      { key: 'estimates', label: 'Estimates' },
      { key: 'website', label: 'Website' },
      { key: 'website_builder', label: 'Website Builder' },
      { key: 'transactions', label: 'Transactions' },
      { key: 'payments', label: 'Payments' },
      { key: 'staff', label: 'Staff' },
      { key: 'services', label: 'Services' },
      { key: 'products', label: 'Products' },
      { key: 'rentals', label: 'Rentals' },
      { key: 'rental_bookings', label: 'Rental Bookings' },
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
  end
end
