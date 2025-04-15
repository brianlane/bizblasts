# frozen_string_literal: true

# Controller for the user dashboard
class DashboardController < ApplicationController
  def index
    if current_user.manager? || current_user.staff?
      # If a business user, they should go to their business manager dashboard
      business = current_user.business
      
      if business
        # Construct the URL for the tenant's dashboard
        host = "#{business.hostname}.#{request.domain}"
        port = request.port unless [80, 443].include?(request.port)
        url = business_manager_dashboard_url(host: host, port: port, protocol: request.protocol)
        
        redirect_to url, allow_other_host: true, status: :see_other and return
      else
        redirect_to root_path, alert: "No business found for your account."
      end
    elsif current_user.client?
      # This is for client users
      @client = current_user
      # Fetch client-specific dashboard data
    else
      redirect_to root_path, alert: "Access denied."
    end
  end

  def set_current_tenant
    ActsAsTenant.current_tenant = current_user.business
  end
end 