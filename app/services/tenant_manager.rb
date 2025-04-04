class TenantManager
  # This service manages tenant-related operations including creation,
  # configuration, and access control

  def self.create_tenant(name, subdomain, timezone, owner_attributes)
    ActiveRecord::Base.transaction do
      # Create the business record
      business = Business.new(
        name: name,
        subdomain: subdomain,
        time_zone: timezone,
        active: true
      )
      
      return [nil, business.errors] unless business.save
      
      # Create the owner user
      user = User.new(
        email: owner_attributes[:email],
        first_name: owner_attributes[:first_name],
        last_name: owner_attributes[:last_name],
        password: owner_attributes[:password],
        password_confirmation: owner_attributes[:password_confirmation],
        role: :admin,
        business: business,
        active: true
      )
      
      unless user.save
        raise ActiveRecord::Rollback
        return [nil, user.errors]
      end
      
      # Initialize with default template if specified
      if owner_attributes[:template_id].present?
        template = Template.find_by(id: owner_attributes[:template_id])
        template&.apply_to_business(business)
      end
      
      [business, nil]
    end
  end
  
  def self.switch_tenant(tenant_identifier)
    # Find the tenant by subdomain or ID
    tenant = if tenant_identifier.is_a?(Integer) || tenant_identifier.to_i.to_s == tenant_identifier
               Business.find_by(id: tenant_identifier)
             else
               Business.find_by(subdomain: tenant_identifier)
             end
             
    return false unless tenant&.active?
    
    # Set the current tenant in the Current object
    Current.business = tenant
    Current.business_id = tenant.id
    
    true
  end
  
  def self.reset_tenant
    Current.reset
  end
  
  def self.provision_tenant_resources(business)
    # This would handle any additional setup needed for a new tenant
    # For example, creating default data, setting up external services, etc.
    
    # Create default pages
    create_default_pages(business)
    
    # Set up default loyalty program
    create_default_loyalty_program(business)
    
    true
  end
  
  private
  
  def self.create_default_pages(business)
    # Create basic pages for the business
    Current.business = business
    
    ['Home', 'About', 'Services', 'Contact'].each do |page_name|
      slug = page_name.downcase
      Page.create(
        title: page_name,
        slug: slug,
        page_type: slug == 'home' ? :home : :custom,
        published: true,
        show_in_menu: true,
        menu_order: ['home', 'about', 'services', 'contact'].index(slug),
        business: business
      )
    end
  end
  
  def self.create_default_loyalty_program(business)
    # Create a basic loyalty program
    LoyaltyProgram.create(
      name: "#{business.name} Rewards",
      points_name: "Points",
      points_for_booking: 10,
      points_for_referral: 50,
      points_per_dollar: 1,
      active: true,
      business: business
    )
  end
end
