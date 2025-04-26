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

      # Find the specific Page record for the current tenant and slug (if using DB pages)
      # @page = current_tenant.pages.find_by(slug: @page_slug, published: true)
      # if @page.nil? && @page_slug != 'home'
      #   render_not_found
      #   return
      # end
      
      # Check if this is a client-specific route we want to handle differently
      if @page_slug == 'my-bookings' && current_user&.client?
        # Let the normal routing handle this - don't try to render a template
        return
      end
      
      # Simplistic approach: Render a view based on the sanitized slug
      # Views should be located in app/views/public/pages/
      template_path = File.join('public', 'pages', @page_slug)
      
      if lookup_context.exists?(@page_slug, 'public/pages', false)
        render template: template_path
      else
        # Log the original requested slug and the sanitized version for debugging
        Rails.logger.warn "[Public::PagesController] Template for raw slug '#{raw_slug}' (sanitized to '#{@page_slug}') not found for tenant #{current_tenant.name}. Rendering home."
        render template: 'public/pages/home'
      end
    end

    private

    def current_tenant
      # Helper to access the tenant set by ActsAsTenant
      ActsAsTenant.current_tenant
    end

    def render_not_found
      render file: Rails.root.join('public/404.html'), layout: false, status: :not_found
    end
    
    # Re-define set_tenant here IF it's private in ApplicationController
    # def set_tenant
    #   # Copy logic from ApplicationController#set_tenant
    # end

  end
end 