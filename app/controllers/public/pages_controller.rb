# frozen_string_literal: true

# Controller for public-facing static pages within a business tenant's subdomain.
module Public
  class PagesController < ApplicationController
    # Ensure tenant is set based on subdomain for all actions in this controller
    # NOTE: This relies on the set_tenant method being defined in ApplicationController
    # and being accessible (e.g., not private or explicitly protected).
    # If set_tenant is private, we need a public wrapper method in ApplicationController
    # or move the tenant setting logic here.
    before_action :set_tenant 
    before_action :ensure_html_format, only: [:show]
    after_action :no_store_cache_headers, only: [:show]

    # Skip user authentication for public pages
    skip_before_action :authenticate_user!

    # GET / (tenant root)
    # GET /about
    # GET /services
    # GET /contact
    # GET /:page
    def show
      # Ensure tenant is set before proceeding
      unless current_tenant
        Rails.logger.warn "[Public::PagesController] Tenant not set for request: #{request.host}"
        # tenant_not_found is likely called by set_tenant if it fails, 
        # but adding a check here for robustness.
        return # Avoid rendering if tenant is somehow nil
      end

      # Determine the page slug from params or default to 'home'
      raw_slug = params[:page].presence || 'home'
      # Sanitize the slug to prevent directory traversal and invalid characters
      @page_slug = raw_slug.gsub(/[^a-zA-Z0-9_\-]+/, '')

      # If sanitization resulted in an empty string, default back to 'home'
      @page_slug = 'home' if @page_slug.blank?

      # PRIORITY: Check for website builder pages FIRST.
      skip_home_builder = (@page_slug == 'home') && current_tenant.website_layout_basic?
      
      if !skip_home_builder
        @page = current_tenant.pages.find_by(slug: @page_slug, status: :published)
        
        if @page.blank? && current_tenant.website_layout_enhanced?
          EnhancedWebsiteLayoutService.apply!(current_tenant)
          @page = current_tenant.pages.find_by(slug: @page_slug, status: :published)
        end
        
        # If we found a website builder page, render it
        if @page.present?
          # Track page view for analytics
          @page.increment_view_count!
          @business = current_tenant
          render template: 'public/pages/website_builder_page'
          return
        end
      end
      
      # Check if this is a client-specific route we want to handle differently
      if @page_slug == 'my-bookings' && current_user&.client?
        # Let the normal routing handle this - don't try to render a template
        return
      end
      
      # Render only known static pages via explicit templates (fallback for free tier or when no custom page exists)
      slug = params[:page].to_s.downcase
      @business = current_tenant # Ensure @business is available for the views

      case slug
      when 'home', 'root', '' # Added root and empty string to explicitly map to home
        # @services are loaded in home.html.erb directly
        # @products are loaded in home.html.erb directly
        render template: 'public/pages/home'
      when 'services'
        @services = @business.services.active.positioned
        if @services.empty?
          redirect_to tenant_root_path, notice: "No services are currently available. Please check back later!"
          return
        end
        render template: 'public/pages/services'
      when 'products'
        # Check for visible products first
        visible_products = @business.products.active.where(product_type: [:standard, :mixed])
                                   .select(&:visible_to_customers?)
        if visible_products.empty?
          redirect_to tenant_root_path, notice: "No products are currently available. Please check back later!"
          return
        end
        
        @products = @business.products.active.where(product_type: [:standard, :mixed])
        @products = @products.where('name ILIKE ?', "%#{params[:q]}%") if params[:q].present?
        @products = @products.positioned
        render template: 'public/pages/products'
      when 'about'
        render template: 'public/pages/about' # Assuming you have an about.html.erb
      when 'contact'
        render template: 'public/pages/contact' # Assuming you have a contact.html.erb
      when 'estimate'
        render template: 'public/pages/estimate'
      else
        # Attempt to render a page with the given slug if a template exists
        # This handles other dynamic pages if you add templates for them
        # e.g. /my-custom-page renders public/pages/my_custom_page.html.erb
        if template_exists?("public/pages/#{slug}")
          render template: "public/pages/#{slug}"
        else
          # Fallback to home if no specific template is found for the slug, 
          # or render 404 if you prefer stricter page definitions.
          # For now, let's redirect to root, or render home to avoid 404 for unknown slugs.
          # render_not_found
          render template: 'public/pages/home' 
        end
      end
    end

    private

    # Force HTML format to prevent JSON template lookup in CI/test environments
    def ensure_html_format
      request.format = :html
    end

    def current_tenant
      # Helper to access the tenant set by ActsAsTenant
      ActsAsTenant.current_tenant
    end

    def render_not_found
      render file: Rails.root.join('public/404.html'), layout: false, status: :not_found
    end
    
    def no_store_cache_headers
      response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
      response.headers["Pragma"]        = "no-cache"
      response.headers["Expires"]       = "0"
    end
    
    # Re-define set_tenant here IF it's private in ApplicationController
    # def set_tenant
    #   # Copy logic from ApplicationController#set_tenant
    # end

  end
end 