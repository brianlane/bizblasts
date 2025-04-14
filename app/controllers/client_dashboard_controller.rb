class ClientDashboardController < ApplicationController
  def index
    if current_user.client?
      # Fetch client-specific dashboard data

      # ...
    else
      redirect_to root_path, alert: "Access denied."
    end
  end
end 