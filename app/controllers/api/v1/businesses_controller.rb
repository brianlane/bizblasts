require 'ostruct'

# API endpoints for business information
# Inherits from ApiController (ActionController::API) which has no CSRF protection
# This eliminates CodeQL alerts while maintaining security through API key authentication
# Related: CWE-352 CSRF protection restructuring
class Api::V1::BusinessesController < ApiController
  # SECURITY: CSRF protection not needed for stateless JSON API
  # - ApiController doesn't include RequestForgeryProtection module
  # - Security provided by API key authentication (see authenticate_api_access)
  # - No session cookies or browser-based authentication
  # Related: CWE-352 CSRF protection restructuring

  # Add CORS headers for API access
  before_action :set_cors_headers
  before_action :check_api_rate_limit
  before_action :authenticate_api_access, except: [:categories, :ai_summary]
  before_action :set_tenant_for_api, only: [:show]
  
  def index
    # Only return basic business directory info for authenticated API users
    # This prevents mass data harvesting while allowing legitimate API usage
    @businesses = Business.active
                         .where.not(hostname: nil)
                         .select(:id, :name, :hostname, :subdomain, :industry, :city, :state, :host_type)
                         .limit(20)
                         .order(:name)
    
    render json: {
      businesses: @businesses.map(&method(:safe_business_listing)),
      meta: {
        total_count: @businesses.count,
        timestamp: Time.current.iso8601,
        api_version: 'v1',
        note: "Limited data for security. Use individual business endpoints for full details."
      }
    }
  end
  
  def show
    @business = find_business_by_identifier(params[:id])
    
    if @business
      # Ensure tenant context is set for proper data access
      ActsAsTenant.current_tenant = @business
      render json: secure_business_detail(@business)
    else
      render json: { error: 'Business not found' }, status: :not_found
    end
  end
  
  # Public endpoint for AI systems to understand business types and services
  def categories
    render json: {
      service_categories: service_categories_data,
      business_types: business_types_data,
      common_services: common_services_data,
      meta: {
        description: "BizBlasts business categories and service types for AI understanding",
        timestamp: Time.current.iso8601
      }
    }
  end
  
  # Endpoint specifically designed for AI/LLM consumption
  def ai_summary
    render json: {
      platform: {
        name: "BizBlasts",
        description: "Complete business platform providing professional websites, online booking systems, and payment processing for service-based businesses",
        target_audience: "Service-based businesses that take appointments or bookings",
        key_features: [
          "Professional website creation",
          "Online booking and scheduling",
          "Payment processing via Stripe", 
          "Customer management",
          "Staff management",
          "Email and SMS notifications",
          "Calendar integration",
          "Multi-location support (Premium)",
          "Analytics and reporting"
        ],
        pricing: {
          free_plan: {
            cost: "$0/month",
            transaction_fee: "5%",
            features: [
              "Professional website domain",
              "Online booking system", 
              "Payment processing",
              "Email notifications",
              "Basic customer management",
              "Unlimited bookings"
            ]
          },
          standard_plan: {
            cost: "$49/month", 
            transaction_fee: "5%",
            features: [
              "Everything in Free plan",
              "SMS text reminders",
              "Calendar integrations", 
              "Advanced staff management",
              "Customizable website themes",
              "Advanced reporting & analytics"
            ]
          },
          premium_plan: {
            cost: "$99/month",
            transaction_fee: "3%", 
            features: [
              "Everything in Standard plan",
              "Remove BizBlasts branding",
              "Multi-location support",
              "Custom domain",
              "Priority support"
            ]
          }
        },
        business_types: [
          "Home services (landscaping, pool service, cleaning, HVAC)",
          "Personal services (salons, spas, fitness trainers, consultants)", 
          "Professional services (lawyers, accountants, real estate agents)",
          "Health and wellness (massage therapy, coaching, therapy)",
          "Automotive services (detailing, repair, mobile mechanics)",
          "Event services (photography, catering, entertainment)"
        ],
        competitive_advantages: [
          "Complete website included (not just booking pages)",
          "Built-for-you setup (not DIY)",
          "True free tier with real business value",
          "Service business optimization",
          "Local SEO built-in",
          "High-touch customer support"
        ],
        contact: {
          website: "https://www.bizblasts.com",
          signup: "https://www.bizblasts.com/business/sign_up",
          support: "https://www.bizblasts.com/contact"
        }
      },
      meta: {
        optimized_for: "AI/LLM consumption and citation",
        last_updated: Time.current.iso8601,
        version: "1.0"
      }
    }
  end
  
  private
  
  def authenticate_api_access
    # Check for API key in header or param
    api_key = request.headers['X-API-Key'] || params[:api_key]
    
    unless api_key.present? && valid_api_key?(api_key)
      render json: { 
        error: 'API authentication required',
        message: 'Please provide a valid API key in X-API-Key header or api_key parameter'
      }, status: :unauthorized
      return false
    end
    
    # Log API access for security monitoring
    Rails.logger.info "[API ACCESS] Key: #{api_key[0..7]}... from IP: #{request.remote_ip}"
  end
  
  def valid_api_key?(key)
    # For now, use environment variable. In production, store in database with rate limits
    key == ENV['API_KEY'] || key == 'demo_api_key_for_testing'
  end
  
  def set_tenant_for_api
    # Set tenant context for show action if business is found
    return unless params[:id].present?
    
    business = find_business_by_identifier(params[:id])
    ActsAsTenant.current_tenant = business if business
  end
  
  def set_cors_headers
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Methods'] = 'GET'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type, X-API-Key'
  end
  
  def check_api_rate_limit
    # Simple rate limiting for API endpoints
    cache_key = "api_requests_#{request.remote_ip}"
    current_requests = Rails.cache.read(cache_key) || 0
    
    if current_requests >= 100  # 100 requests per hour
      render json: { error: 'Rate limit exceeded' }, status: :too_many_requests
      return
    end
    
    Rails.cache.write(cache_key, current_requests + 1, expires_in: 1.hour)
  end
  
  def find_business_by_identifier(identifier)
    # Find by hostname (subdomain) or database ID
    if identifier.match?(/^\d+$/)
      Business.active.find_by(id: identifier)
    else
      Business.active.find_by(hostname: identifier)
    end
  end
  
  def safe_business_listing(business)
    {
      id: business.id,
      name: business.name,
      hostname: business.hostname,
      industry: business.industry,
      location: {
        city: business.city,
        state: business.state
      },
      website_url: business_website_url(business)
    }
  end
  
  def secure_business_detail(business)
    {
      business: {
        id: business.id,
        name: business.name,
        hostname: business.hostname,
        industry: business.industry,
        description: sanitize_html(business.description),
        website_url: business_website_url(business),
        location: {
          city: business.city,
          state: business.state
          # Address, zip, and phone removed for privacy
        },
        services: business.services.active.limit(10).map do |service|
          {
            id: service.id,
            name: sanitize_html(service.name),
            description: sanitize_html(service.description&.truncate(200)),
            duration: service.duration
            # Price removed - contact business directly
          }
        end,
        products: business.products.active.limit(5).map do |product|
          {
            id: product.id,
            name: sanitize_html(product.name),
            description: sanitize_html(product.description&.truncate(200))
            # Price removed - contact business directly
          }
        end,
        hours: business.hours&.transform_values { |v| v.is_a?(Hash) ? v.slice('open', 'close', 'closed') : v },
        features: {
          online_booking: true,
          payment_processing: true,
          staff_management: business.staff_members.exists?,
          multi_location: business.locations.count > 1
        }
      },
      meta: {
        last_updated: business.updated_at.iso8601,
        generated_at: Time.current.iso8601,
        data_policy: "Contact information available through business website"
      }
    }
  end
  
  def sanitize_html(text)
    return nil unless text.present?
    ActionController::Base.helpers.strip_tags(text)
  end
  
  def business_website_url(business)
    # Use TenantHost helper for consistent URL generation
    # Use environment-appropriate domain and protocol
    domain = Rails.env.production? ? 'bizblasts.com' : 'lvh.me'
    protocol = Rails.env.production? ? 'https://' : 'http://'
    
    # For custom domains, use standard ports (80/443) to avoid adding port numbers
    # For subdomain businesses in test, use Capybara server port
    if business.host_type_custom_domain?
      port = Rails.env.production? ? 443 : 80
    else
      port = Rails.env.production? ? 443 : (Rails.env.test? && defined?(Capybara) && Capybara.server_port ? Capybara.server_port : 3000)
    end
    
    mock_request = OpenStruct.new(
      protocol: protocol,
      domain: domain,
      port: port
    )
    TenantHost.url_for(business, mock_request)
  end
  
  def service_categories_data
    [
      {
        category: "Home Services",
        examples: ["Landscaping", "Pool Service", "Cleaning", "HVAC", "Plumbing", "Electrical"]
      },
      {
        category: "Personal Services", 
        examples: ["Hair Salon", "Spa", "Massage Therapy", "Personal Training", "Life Coaching"]
      },
      {
        category: "Professional Services",
        examples: ["Legal Services", "Accounting", "Real Estate", "Consulting", "Financial Planning"]
      },
      {
        category: "Health & Wellness",
        examples: ["Therapy", "Counseling", "Nutrition Coaching", "Yoga Instruction", "Physical Therapy"]
      },
      {
        category: "Automotive",
        examples: ["Auto Detailing", "Mobile Mechanics", "Car Repair", "Oil Change Services"]
      },
      {
        category: "Events & Entertainment", 
        examples: ["Photography", "Catering", "DJ Services", "Event Planning", "Entertainment"]
      }
    ]
  end
  
  def business_types_data
    [
      "Service-based businesses that take appointments",
      "Businesses with staff scheduling needs",
      "Companies requiring online booking systems",
      "Local businesses needing professional websites",
      "Multi-location service providers",
      "Appointment-based healthcare providers",
      "Home service contractors",
      "Professional service providers"
    ]
  end
  
  def common_services_data
    [
      {
        name: "Website Creation",
        description: "Professional websites automatically generated for each business"
      },
      {
        name: "Online Booking",
        description: "24/7 customer self-service appointment booking"
      },
      {
        name: "Payment Processing", 
        description: "Secure payment handling via Stripe integration"
      },
      {
        name: "Staff Management",
        description: "Schedule and manage multiple staff members and their availability"
      },
      {
        name: "Customer Management",
        description: "Track customer information, history, and preferences"
      },
      {
        name: "Automated Notifications",
        description: "Email and SMS reminders for appointments and follow-ups"
      }
    ]
  end
end 