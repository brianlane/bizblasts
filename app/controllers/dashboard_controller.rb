# frozen_string_literal: true

# Controller for the user dashboard
class DashboardController < ApplicationController
  def index
    @company = ActsAsTenant.current_tenant || Company.find_by(id: current_user&.company_id)
    
    # Fallback if tenant can't be determined
    unless @company
      flash[:alert] = "Could not determine your company."
      redirect_to root_path and return
    end
  end
end 