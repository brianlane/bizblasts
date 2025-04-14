class AdminDashboardController < ApplicationController
  def index
    if current_user.admin?
      # Fetch admin-specific dashboard data across all tenants
    else
      redirect_to root_path, alert: "Access denied."
    end
  end
end 