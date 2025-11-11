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
        flash.now[:alert] = "We couldn't find that ZIP code. Please double-check and try again."
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

      uri = URI.parse(proposed) rescue nil
      if uri&.host.present? && uri.host != request.host
        fallback
      else
        uri&.path.present? ? uri.to_s : proposed
      end
    end
  end
end

