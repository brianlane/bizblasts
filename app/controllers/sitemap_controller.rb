class SitemapController < ApplicationController
  # Skip authentication - sitemap must be publicly accessible for search engines
  skip_before_action :authenticate_user!
  
  # Add basic security headers and rate limiting
  before_action :set_security_headers
  before_action :check_rate_limit
  
  # Cache the sitemap for performance and to reduce database load
  before_action :set_cache_headers
  
  def index
    # Sanitize and validate the base URL
    @base_url = sanitize_base_url
    
    # Static pages with their priorities and change frequencies
    @static_pages = [
      { url: root_path, priority: 1.0, changefreq: 'daily' },
      { url: '/about', priority: 0.8, changefreq: 'monthly' },
      { url: '/contact', priority: 0.8, changefreq: 'monthly' },
      { url: '/pricing', priority: 0.9, changefreq: 'weekly' },
      { url: '/businesses', priority: 0.9, changefreq: 'daily' },
      { url: '/blog', priority: 0.8, changefreq: 'daily' },
      { url: '/docs', priority: 0.7, changefreq: 'weekly' }
    ]
    
    # Add blog posts if they exist - only published and public posts
    @blog_posts = fetch_public_blog_posts
    
    # Add business subdomain URLs - these help with discoverability
    @businesses = fetch_business_subdomains
    
    respond_to do |format|
      format.xml { render layout: false }
    end
  end
  
  private
  
  def set_security_headers
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['X-Frame-Options'] = 'DENY'
    response.headers['X-XSS-Protection'] = '1; mode=block'
  end
  
  def set_cache_headers
    # Cache for 1 hour to reduce server load
    expires_in 1.hour, public: true
  end
  
  def check_rate_limit
    # Simple rate limiting - allow 60 requests per hour per IP
    cache_key = "sitemap_requests_#{request.remote_ip}"
    current_requests = Rails.cache.read(cache_key) || 0
    
    if current_requests >= 60
      render xml: '<?xml version="1.0" encoding="UTF-8"?><error>Rate limit exceeded</error>', 
             status: :too_many_requests
      return
    end
    
    Rails.cache.write(cache_key, current_requests + 1, expires_in: 1.hour)
  end
  
  def sanitize_base_url
    # Only allow HTTPS and sanitize the host
    protocol = request.ssl? ? 'https://' : 'http://'
    host = request.host
    
    # Validate host against allowed domains (add your domains here)
    allowed_hosts = [
      'bizblasts.com',
      'www.bizblasts.com',
      'localhost'
    ]
    
    unless allowed_hosts.include?(host) || Rails.env.development?
      host = 'www.bizblasts.com'
    end
    
    port = (request.port == 80 || request.port == 443) ? '' : ":#{request.port}"
    "#{protocol}#{host}#{port}"
  end
  
  def fetch_public_blog_posts
    return [] unless defined?(BlogPost)
    
    # Only include published, public blog posts
    BlogPost.published
            .where.not(slug: nil) # Ensure slug exists
            .order(created_at: :desc)
            .limit(100)
            .pluck(:slug, :updated_at)
            .map do |slug, updated_at|
              {
                url: "/blog/#{ERB::Util.url_encode(slug)}",
                priority: 0.6,
                changefreq: 'weekly',
                lastmod: updated_at
              }
            end
  rescue => e
    Rails.logger.error "Error fetching blog posts for sitemap: #{e.message}"
    []
  end
  
  def fetch_business_subdomains
    return [] unless defined?(Business)
    
    # Only include active businesses with valid hostnames
    scope = Business.where.not(hostname: nil)
    
    # Add additional filters if these columns exist
    scope = scope.where(active: true) if Business.column_names.include?('active')
    
    scope.order(updated_at: :desc)
         .limit(100)
         .pluck(:hostname, :host_type, :updated_at)
         .map do |hostname, host_type, updated_at|
           # Generate the correct URL based on host type
           if host_type == 'custom_domain'
             full_url = "https://#{hostname}"
           else
             # Subdomain on bizblasts.com
             full_url = "https://#{hostname}.bizblasts.com"
           end
           
           {
             url: full_url,
             priority: 0.8,
             changefreq: 'weekly',
             lastmod: updated_at
           }
         end
  rescue => e
    Rails.logger.error "Error fetching business subdomains for sitemap: #{e.message}"
    []
  end
end 