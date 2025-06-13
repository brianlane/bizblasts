class Api::V1::BusinessesController < ApplicationController
  # Skip authentication for public API endpoints that LLMs need to access
  skip_before_action :authenticate_user!
  skip_before_action :verify_authenticity_token
  
  # Add CORS headers for API access
  before_action :set_cors_headers
  before_action :check_api_rate_limit
  
  def index
    @businesses = Business.active
                         .where.not(hostname: nil)
                         .includes(:services, :products)
                         .limit(50)
                         .order(:name)
    
    render json: {
      businesses: @businesses.map(&method(:business_summary)),
      meta: {
        total_count: @businesses.count,
        timestamp: Time.current.iso8601,
        api_version: 'v1'
      }
    }
  end
  
  def show
    @business = find_business_by_identifier(params[:id])
    
    if @business
      render json: business_detail(@business)
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
  
  def set_cors_headers
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Methods'] = 'GET'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type'
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
  
  def business_summary(business)
    {
      id: business.id,
      name: business.name,
      hostname: business.hostname,
      industry: business.industry,
      description: business.description&.truncate(200),
      website_url: business_website_url(business),
      location: {
        city: business.city,
        state: business.state,
        address: business.address
      },
      services_count: business.services.count,
      contact: {
        phone: business.phone,
        email: business.email
      }
    }
  end
  
  def business_detail(business)
    {
      business: {
        id: business.id,
        name: business.name,
        hostname: business.hostname,
        industry: business.industry,
        description: business.description,
        website_url: business_website_url(business),
        location: {
          address: business.address,
          city: business.city,
          state: business.state,
          zip: business.zip
        },
        contact: {
          phone: business.phone,
          email: business.email,
          website: business.website
        },
        social_media: {
          facebook: business.facebook_url,
          twitter: business.twitter_url,
          instagram: business.instagram_url,
          linkedin: business.linkedin_url
        },
        services: business.services.map do |service|
          {
            id: service.id,
            name: service.name,
            description: service.description,
            price: service.price,
            duration: service.duration
          }
        end,
        products: business.products.limit(10).map do |product|
          {
            id: product.id,
            name: product.name,
            description: product.description,
            price: product.price
          }
        end,
        hours: business.hours,
        features: {
          online_booking: true,
          payment_processing: true,
          staff_management: true,
          multi_location: business.tier == 'premium'
        }
      },
      meta: {
        last_updated: business.updated_at.iso8601,
        generated_at: Time.current.iso8601
      }
    }
  end
  
  def business_website_url(business)
    if business.host_type == 'custom_domain'
      "https://#{business.hostname}"
    else
      "https://#{business.hostname}.bizblasts.com"
    end
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