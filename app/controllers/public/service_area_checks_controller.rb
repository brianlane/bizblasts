module Public
  class ServiceAreaChecksController < ApplicationController
    skip_before_action :authenticate_user!

    def new
      @service = current_tenant.services.find_by(id: params[:service_id])
      @return_to = safe_return_path(params[:return_to], @service)
    end

    def create
      @service = current_tenant.services.find_by(id: params[:service_id])
      @return_to = safe_return_path(params[:return_to], @service)
      zip = params.dig(:service_area_check, :zip).to_s.strip

      if zip.blank?
        flash.now[:alert] = "Please enter a ZIP code."
        return render :new, status: :unprocessable_entity
      end

      policy = current_tenant.booking_policy
      checker = ServiceAreaChecker.new(current_tenant)
      radius_miles = policy&.effective_service_radius_miles || ServiceAreaChecker::DEFAULT_RADIUS_MILES

      result = checker.within_radius?(zip, radius_miles: radius_miles)

      case result
      when true
        flash[:notice] = "Great news! We service your area."
        redirect_to @return_to
      when :invalid_zip
        flash.now[:alert] = "We couldn't find that ZIP code. Please double-check and try again.".html_safe
        render :new, status: :unprocessable_entity
      else
        flash.now[:alert] = "It looks like you're outside our service area. Please contact us to see if we can make an exception."
        render :new, status: :unprocessable_entity
      end
    end

    private

    def safe_return_path(proposed, service)
      fallback = if service.present?
                   new_tenant_booking_path(service_id: service.id)
                 else
                   tenant_calendar_path
                 end

      return fallback if proposed.blank?

      # Parse and validate the proposed URL
      begin
        uri = URI.parse(proposed)

        # Explicitly reject dangerous schemes (XSS prevention)
        # Only allow HTTP/HTTPS or no scheme at all (relative paths)
        if uri.scheme.present?
          dangerous_schemes = %w[javascript data vbscript file]
          return fallback if dangerous_schemes.include?(uri.scheme.downcase)

          # Only allow http/https schemes if a scheme is present
          return fallback unless %w[http https].include?(uri.scheme.downcase)
        end

        # Reject any URL with a host (including protocol-relative URLs)
        # Only allow relative paths to prevent open redirects
        return fallback if uri.host.present?

        # Only return the path component, never a full URL
        # This prevents open redirect attacks by ensuring we never redirect to external sites
        path = uri.path.presence
        return fallback if path.blank?

        # Include query string if present (but still path-only)
        path += "?#{uri.query}" if uri.query.present?
        path
      rescue URI::InvalidURIError
        # If URL parsing fails, return safe fallback
        fallback
      end
    end
  end
end

