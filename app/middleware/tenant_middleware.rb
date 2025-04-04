class TenantMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)
    domain = request.host.downcase
    
    # Extract subdomain or use custom domain to identify tenant
    tenant = find_tenant_from_request(domain)
    
    if tenant
      # Set current tenant for this request
      set_current_tenant(tenant) do
        @app.call(env)
      end
    else
      # No tenant found, redirect to marketing site or show error
      handle_missing_tenant(env)
    end
  end
  
  private
  
  def find_tenant_from_request(domain)
    # Try to find by custom domain first
    tenant = find_by_custom_domain(domain)
    
    # If not found, try by subdomain
    tenant ||= find_by_subdomain(domain.split('.').first) unless domain =~ /^www\./
    
    tenant
  end
  
  def find_by_custom_domain(domain)
    # Find business by custom domain
    Business.find_by(custom_domain: domain, active: true)
  end
  
  def find_by_subdomain(subdomain)
    return nil if subdomain.blank? || %w[www admin api].include?(subdomain)
    
    # Find business by subdomain
    Business.find_by(subdomain: subdomain, active: true)
  end
  
  def set_current_tenant(tenant, &block)
    # Set the current tenant in the Current object
    previous_tenant = Current.business
    previous_tenant_id = Current.business_id
    
    begin
      Current.business = tenant
      Current.business_id = tenant.id
      
      yield
    ensure
      # Reset back to original tenant when done
      Current.business = previous_tenant
      Current.business_id = previous_tenant_id
    end
  end
  
  def handle_missing_tenant(env)
    request = Rack::Request.new(env)
    host = request.host
    
    if host =~ /^www\./ || !host.include?('.') || %w[localhost 127.0.0.1].include?(host)
      # Main marketing site, allow request to proceed
      @app.call(env)
    else
      # Tenant not found, show error
      [404, {'Content-Type' => 'text/html'}, ['Business not found. Please check the URL and try again.']]
    end
  end
end
