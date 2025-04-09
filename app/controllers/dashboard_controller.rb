# frozen_string_literal: true

# Controller for the user dashboard
class DashboardController < ApplicationController
  def index
    @business = ActsAsTenant.current_tenant || Business.find_by(id: current_user&.business_id)
    
    # Fallback if tenant can't be determined
    unless @business
      flash[:alert] = "Could not determine your business."
      redirect_to root_path and return
    end
  end
end 