# frozen_string_literal: true

# Service to check business setup completion and generate todo items
class BusinessSetupService
  include Rails.application.routes.url_helpers

  def initialize(business)
    @business = business
  end

  # Check if the business setup is complete (only essential items)
  def setup_complete?
    essential_todo_items.empty?
  end

  # Get all pending todo items for the business (essential + suggestions)
  def todo_items
    essential_todo_items + suggestion_items
  end

  # Get only the essential setup items
  def essential_todo_items
    items = []
    
    # 1. Connect to Stripe (ESSENTIAL)
    unless stripe_connected?
      items << {
        text: "Connect your Stripe account to accept payments",
        action: "Set up Stripe",
        url: edit_business_manager_settings_business_path,
        priority: :high,
        essential: true
      }
    end

    # 2. Add service or product (ESSENTIAL)
    unless has_services_or_products?
      items << {
        text: "Add your first service or product to start taking orders",
        action: "Add Service",
        url: new_business_manager_service_path,
        priority: :high,
        essential: true
      }
    end

    # 3. Add Availability (ESSENTIAL - Only if they added a service)
    if has_services? && !has_staff_availability?
      items << {
        text: "Set staff availability for your services",
        action: "Manage Availability",
        url: business_manager_staff_members_path,
        priority: :medium,
        essential: true
      }
    end

    # 4. Add Shipping (ESSENTIAL - Only if they added a product)
    if has_products? && !has_shipping_methods?
      items << {
        text: "Set up shipping methods for your products",
        action: "Add Shipping",
        url: business_manager_shipping_methods_path,
        priority: :medium,
        essential: true
      }
    end

    # 5. Configure Tax Rates (ESSENTIAL)
    unless has_tax_rates?
      items << {
        text: "Configure tax rates for your location",
        action: "Set Tax Rates",
        url: business_manager_tax_rates_path,
        priority: :low,
        essential: true
      }
    end

    items
  end

  # Get nice-to-have suggestion items
  def suggestion_items
    items = []

    # 6. Add staff members (SUGGESTION - if only the owner exists)
    if needs_additional_staff?
      items << {
        text: "Add staff members to help manage your business",
        action: "Add Staff",
        url: new_business_manager_staff_member_path,
        priority: :low,
        essential: false
      }
    end

    # 7. Customize business profile (SUGGESTION)
    unless has_complete_business_profile?
      items << {
        text: "Complete your business profile with description and contact info",
        action: "Edit Profile",
        url: edit_business_manager_settings_business_path,
        priority: :low,
        essential: false
      }
    end

    items
  end

  # Get high priority items only
  def high_priority_items
    todo_items.select { |item| item[:priority] == :high }
  end

  # Get a summary for display
  def setup_summary
    essential_items = essential_todo_items.count
    total_items = todo_items.count
    high_priority = high_priority_items.count
    
    if essential_items == 0
      "Your business setup is complete! 🎉"
    else
      "#{total_items} setup task#{'s' if total_items != 1} remaining (#{high_priority} high priority)"
    end
  end

  private

  attr_reader :business

  def stripe_connected?
    business.stripe_account_id.present?
  end

  def has_services_or_products?
    has_services? || has_products?
  end

  def has_services?
    business.services.active.exists?
  end

  def has_products?
    business.products.active.exists?
  end

  def has_staff_availability?
    # Check if any staff member has availability set
    business.staff_members.active.any? do |staff|
      availability = staff.availability
      availability.is_a?(Hash) && 
      availability.any? { |day, slots| day != 'exceptions' && slots.present? && slots.any? }
    end
  end

  def has_shipping_methods?
    business.shipping_methods.active.exists?
  end

  def has_tax_rates?
    business.tax_rates.exists?
  end

  def needs_additional_staff?
    # Only suggest adding staff if they have services and only one staff member (the owner)
    has_services? && business.staff_members.active.count <= 1
  end

  def has_complete_business_profile?
    # Check if business has description and other important fields filled
    business.description.present? && 
    business.phone.present? && 
    business.email.present? &&
    business.address.present?
  end
end 