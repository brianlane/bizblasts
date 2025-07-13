# frozen_string_literal: true

# SidebarItems is a tiny PORO that encapsulates all configuration needed to
# build each sidebar link. Using a hash + lambdas keeps our view-helpers small
# and avoids RuboCop complexity offences.

module SidebarItems
  # Helper constant to avoid repeating the common fallback array.
  FALLBACK = [nil, nil, nil, nil, false].freeze

  # rubocop:disable Layout/LineLength
  CONFIG = {
    dashboard:              { path: -> { business_manager_dashboard_path }, icon: '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2V6zM14 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V6zM4 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2v-2zM14 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z"/></svg>' },
    bookings:               { path: -> { business_manager_bookings_path }, icon: '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"/></svg>' },

    website:                { path: -> { current_business&.full_url || '#' }, icon: '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9v-9m0-9v9m0 9c-5 0-9-4-9-9s4-9 9-9" /></svg>', label: 'Website', extra_svg: '<svg class="w-4 h-4 ml-auto flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" /></svg>', new_tab: true },

    website_builder:        { path: -> { business_manager_website_pages_path }, icon: '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" /></svg>', condition: -> { current_business&.standard_tier? || current_business&.premium_tier? } },

    transactions:           { path: -> { business_manager_transactions_path }, icon: '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01" /></svg>' },
    payments:               { path: -> { business_manager_payments_path }, icon: '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 9V7a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2m2 4h10a2 2 0 002-2v-6a2 2 0 00-2-2H9a2 2 0 00-2 2v6a2 2 0 002 2zm7-5a2 2 0 11-4 0 2 2 0 014 0z" /></svg>' },
    staff:                  { path: -> { business_manager_staff_members_path }, icon: '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" /></svg>' },
    services:               { path: -> { business_manager_services_path }, icon: '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4" /></svg>' },
    products:               { path: -> { business_manager_products_path }, icon: '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4" /></svg>' },
    shipping_methods:       { path: -> { business_manager_shipping_methods_path }, icon: '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 9l3 3-3 3m5 0h3M5 20h14a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" /></svg>' },
    tax_rates:              { path: -> { business_manager_tax_rates_path }, icon: '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 7h6m0 10v-3m-3 3h.01M9 17h.01M9 14h.01M12 14h.01M15 11h.01M12 11h.01M9 11h.01M7 21h10a2 2 0 002-2V5a2 2 0 00-2-2H7a2 2 0 00-2 2v14a2 2 0 002 2z" /></svg>' },

    customers:              { path: -> { business_manager_customers_path }, icon: '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" /></svg>' },
    referrals:              { path: -> { business_manager_referrals_path }, icon: '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="currentColor" viewBox="0 0 490.064 490.064">
                                                                                        <g>
                                                                                            <g>
                                                                                                <path d="M332.682,167.764c34.8-32.7,50.7-74.7,57.6-100.7c3.9-14.6,1.6-56.9-41.5-65.6c-21.3-4.3-50.5,1.2-86,12.2
                                                                                                c-11.6,3.6-23.8,3.6-35.4,0c-35.6-11-64.7-16.1-86-12.2c-40.9,7.4-45.4,51-41.5,65.6c6.9,26,22.8,67.9,57.6,100.6
                                                                                                c-57.7,24.5-98.4,83.5-98.4,152.5v149.3c0,10.8,8.3,20.6,19.7,20.6h331.5c11.4,0,19.7-9.7,20.7-20.6v-149.3
                                                                                                C431.082,251.164,390.382,192.164,332.682,167.764z M139.082,55.664c-1-3.7-0.1-11.4,7.5-12c10.9-0.8,31.7-0.8,69.2,10.8
                                                                                                c19.2,5.9,39.4,5.9,58.6,0c37.5-11.6,58.3-12.1,69.2-10.8c10.5,1.2,8.5,8.3,7.5,12c-7.2,26.9-26.2,75.1-73.1,100.1
                                                                                                c-1.5,0-2.9-0.1-4.4-0.1h-57c-1.5,0-2.9,0-4.4,0.1C165.282,130.764,146.282,82.564,139.082,55.664z M390.682,448.964h-291.2
                                                                                                v-128.8c0-67.1,51.8-122.3,117.1-122.3h57c64.2,0,117.1,54.1,117.1,122.3V448.964z"/>
                                                                                                <path d="M245.082,311.464c-8.4,0-15.3-6.9-15.3-15.3s6.9-15.3,15.3-15.3c4.3,0,8.2,1.7,11.2,4.8c5.9,6.3,15.8,6.6,22.1,0.7
                                                                                                c6.3-5.9,6.6-15.8,0.7-22.1c-5.1-5.4-11.4-9.5-18.3-11.9v-6.3c0-8.7-7-15.7-15.7-15.7s-15.7,7-15.7,15.7v6.2
                                                                                                c-18,6.5-31,23.7-31,43.9c0,25.7,20.9,46.7,46.7,46.7c8.4,0,15.3,6.9,15.3,15.3s-6.9,15.3-15.3,15.3c-4.3,0-8.2-1.7-11.2-4.8
                                                                                                c-5.9-6.3-15.8-6.6-22.1-0.7s-6.6,15.8-0.7,22.1c5.1,5.4,11.4,9.5,18.3,11.9v6.3c0,8.7,7,15.7,15.7,15.7s15.7-7,15.7-15.7v-6.2
                                                                                                c18-6.5,31-23.7,31-43.9C291.782,332.364,270.782,311.464,245.082,311.464z"/>
                                                                                            </g>
                                                                                        </g>
                                                                                    </svg>' },
    loyalty:                { path: -> { business_manager_loyalty_index_path }, icon: '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                                                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11.049 2.927c.3-.921 1.603-.921 1.902 0l1.519 4.674a1 1 0 00.95.69h4.915c.969 0 1.371 1.24.588 1.81l-3.976 2.888a1 1 0 00-.363 1.118l1.518 4.674c.3.922-.755 1.688-1.538 1.118l-3.976-2.888a1 1 0 00-1.176 0l-3.976 2.888c-.783.57-1.838-.197-1.538-1.118l1.518-4.674a1 1 0 00-.363-1.118l-3.976-2.888c-.784-.57-.38-1.81.588-1.81h4.914a1 1 0 00.951-.69l1.519-4.674z"/>
                                                                                        </svg>' },
    platform:               { path: -> { business_manager_platform_index_path }, icon: '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" /></svg>' },
    promotions:             { path: -> { business_manager_promotions_path }, icon: '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z" /></svg>' },
    customer_subscriptions: { path: -> { business_manager_customer_subscriptions_path }, icon: '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" /></svg>' },
    settings:               { path: -> { business_manager_settings_path }, icon: '<svg class="w-5 h-5 mr-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" /><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" /></svg>' }
  }.freeze
  # rubocop:enable Layout/LineLength

  module_function

  # Returns the 5-element array expected by the sidebar views.
  # 0. path        – String | nil
  # 1. icon_svg    – String (can be empty to skip rendering)
  # 2. label       – String | nil
  # 3. extra_svg   – String | nil
  # 4. new_tab?    – Boolean
  def fetch(item_key, context)
    cfg = CONFIG[item_key.to_sym]
    return FALLBACK unless cfg

    return FALLBACK if cfg[:condition] && !context.instance_exec(&cfg[:condition])

    path = context.instance_exec(&cfg[:path])
    return FALLBACK unless path

    [
      path,
      cfg[:icon] || '',
      cfg[:label],
      cfg[:extra_svg],
      cfg.fetch(:new_tab, false)
    ]
  end
end
