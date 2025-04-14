# frozen_string_literal: true

# Controller for the user dashboard
class DashboardController < ApplicationController
  def index
    if current_user.manager?
      @business = ActsAsTenant.current_tenant
      # Fetch manager-specific dashboard data scoped to @business
    else
      redirect_to root_path, alert: "Access denied."
    end
  end

  def set_current_tenant
    ActsAsTenant.current_tenant = current_user.business
  end
end 