# frozen_string_literal: true

# Service to check business setup completion and generate todo items
class BusinessSetupService
  include Rails.application.routes.url_helpers

  # Initialize service with business context and optional user for dismissals
  def initialize(business, user = nil)
    @business = business
    @user = user
  end

  # Check if the business setup is complete (only essential items)
  def setup_complete?
    essential_todo_items.empty?
  end

  # Get all pending todo items for the business (essential + suggestions)
  def todo_items
    all_items = essential_todo_items + suggestion_items
    # If no user is provided, show all items
    return all_items unless user

    # Filter out any items the user has dismissed
    dismissed_keys = user.setup_reminder_dismissals.pluck(:task_key)
    all_items.reject { |item| dismissed_keys.include?(item[:key].to_s) }
  end

  # Get only the essential setup items
  def essential_todo_items
    items = []
    
    # 1. Connect to Stripe (ESSENTIAL)
    unless stripe_connected?
      items << {
        key: :stripe_connected,
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
        key: :add_service_or_product,
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
        key: :set_staff_availability,
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
        key: :add_shipping_methods,
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
        key: :configure_tax_rates,
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
        key: :add_staff_members,
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
        key: :complete_business_profile,
        text: "Complete your business profile with description and contact info",
        action: "Edit Profile",
        url: edit_business_manager_settings_business_path,
        priority: :low,
        essential: false
      }
    end

    # 8. Establish loyalty program (SUGGESTION)
    unless has_loyalty_program_enabled?
      items << {
        key: :establish_loyalty_program,
        text: "Set up a loyalty program to reward repeat customers",
        action: "Set up Loyalty",
        url: business_manager_loyalty_index_path,
        priority: :low,
        essential: false
      }
    end

    # 9. Establish referral program (SUGGESTION)
    unless has_referral_program_enabled?
      items << {
        key: :establish_referral_program,
        text: "Create a referral program to grow through word-of-mouth",
        action: "Set up Referrals",
        url: business_manager_referrals_path,
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

  attr_reader :business, :user

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

  def has_loyalty_program_enabled?
    business.loyalty_program_enabled?
  end

  def has_referral_program_enabled?
    business.referral_program_enabled?
  end
end 