# frozen_string_literal: true

# Helper for business registration sidebar selection
module BusinessRegistrationsHelper
  # Returns sidebar items suitable for registration form selection
  # Delegates to SidebarItems - the single source of truth
  def sidebar_registration_items
    SidebarItems.registration_items
  end
end
